import 'dart:convert';

import 'package:chat_proxy/chat_proxy.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class FakeProvider implements ChatProvider {
  FakeProvider(this._reply);

  final Stream<String> Function() _reply;
  List<ChatTurn>? receivedMessages;
  String? receivedSystem;

  @override
  String get name => 'Fake';

  @override
  Stream<String> stream(List<ChatTurn> messages, {String? system}) {
    receivedMessages = messages;
    receivedSystem = system;
    return _reply();
  }
}

const _validChat =
    '{"provider":"claude",'
    '"messages":[{"role":"user","content":"Hi"}]}';

const _chatWithSystemPrompt =
    '{"provider":"claude",'
    '"system":"Answer like a pirate.",'
    '"messages":[{"role":"user","content":"Hi"}]}';

void main() {
  Future<Response> send(
    Handler handler,
    String method,
    String path, {
    String? body,
  }) async {
    return handler(
      Request(method, Uri.parse('http://localhost$path'), body: body),
    );
  }

  Handler handlerWith(
    FakeProvider provider, {
    String? systemPrompt,
    bool allowClientSystemPrompt = true,
    Duration heartbeatInterval = const Duration(seconds: 15),
  }) {
    return buildHandler(
      providers: {'claude': provider},
      systemPrompt: systemPrompt,
      allowClientSystemPrompt: allowClientSystemPrompt,
      heartbeatInterval: heartbeatInterval,
    );
  }

  Handler idleHandler() =>
      handlerWith(FakeProvider(() => const Stream.empty()));

  test('GET /health lists the configured providers', () async {
    final response = await send(idleHandler(), 'GET', '/health');

    expect(response.statusCode, 200);
    expect(jsonDecode(await response.readAsString()), {
      'status': 'ok',
      'providers': ['claude'],
    });
  });

  test('adds CORS headers and answers preflight requests', () async {
    final handler = idleHandler();

    final preflight = await send(handler, 'OPTIONS', '/chat');
    final health = await send(handler, 'GET', '/health');

    expect(preflight.statusCode, 204);
    expect(preflight.headers['access-control-allow-methods'], contains('POST'));
    expect(preflight.headers['access-control-allow-headers'], 'content-type');
    expect(health.headers['access-control-allow-origin'], '*');
  });

  test('POST /chat streams deltas followed by done', () async {
    final provider = FakeProvider(() => Stream.fromIterable(['Hel', 'lo']));
    final handler = handlerWith(provider, systemPrompt: 'Be kind.');

    final response = await send(handler, 'POST', '/chat', body: _validChat);

    expect(response.statusCode, 200);
    expect(response.headers['content-type'], startsWith('text/event-stream'));
    expect(
      await response.readAsString(),
      'data: {"type":"delta","text":"Hel"}\n\n'
      'data: {"type":"delta","text":"lo"}\n\n'
      'data: {"type":"done"}\n\n',
    );
    expect(provider.receivedMessages?.single.content, 'Hi');
    expect(provider.receivedSystem, 'Be kind.');
  });

  test('a system prompt in the request overrides the default', () async {
    final provider = FakeProvider(() => const Stream.empty());
    final handler = handlerWith(provider, systemPrompt: 'Default prompt.');

    final response = await send(
      handler,
      'POST',
      '/chat',
      body: _chatWithSystemPrompt,
    );
    await response.readAsString();

    expect(provider.receivedSystem, 'Answer like a pirate.');
  });

  test(
    'the request system prompt is ignored when the server disallows it',
    () async {
      final provider = FakeProvider(() => const Stream.empty());
      final handler = handlerWith(
        provider,
        systemPrompt: 'Default prompt.',
        allowClientSystemPrompt: false,
      );

      final response = await send(
        handler,
        'POST',
        '/chat',
        body: _chatWithSystemPrompt,
      );
      await response.readAsString();

      expect(provider.receivedSystem, 'Default prompt.');
    },
  );

  test('sends keep-alive comments while the provider is silent', () async {
    Stream<String> slowReply() async* {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      yield 'Hi';
    }

    final handler = handlerWith(
      FakeProvider(slowReply),
      heartbeatInterval: const Duration(milliseconds: 20),
    );

    final response = await send(handler, 'POST', '/chat', body: _validChat);
    final body = await response.readAsString();

    expect(body, startsWith(heartbeatComment));
    expect(
      body,
      endsWith(
        'data: {"type":"delta","text":"Hi"}\n\n'
        'data: {"type":"done"}\n\n',
      ),
    );
  });

  test('a provider failure becomes a single error event', () async {
    Stream<String> failingReply() async* {
      yield 'Hel';
      throw const ProviderException('Claude is overloaded right now.');
    }

    final handler = handlerWith(FakeProvider(failingReply));

    final response = await send(handler, 'POST', '/chat', body: _validChat);

    expect(
      await response.readAsString(),
      'data: {"type":"delta","text":"Hel"}\n\n'
      'data: {"type":"error","message":"Claude is overloaded right now."}\n\n',
    );
  });

  test('unexpected errors are reported without internal details', () async {
    final handler = handlerWith(
      FakeProvider(() => Stream.error(StateError('db password is hunter2'))),
    );

    final response = await send(handler, 'POST', '/chat', body: _validChat);
    final body = await response.readAsString();

    expect(body, startsWith('data: {"type":"error"'));
    expect(body, isNot(contains('hunter2')));
  });

  test('names the provider when it has no API key', () async {
    final response = await send(
      idleHandler(),
      'POST',
      '/chat',
      body: '{"provider":"openai","messages":[{"role":"user","content":"Hi"}]}',
    );

    expect(response.statusCode, 400);
    expect(jsonDecode(await response.readAsString()), {
      'error': 'The chat server has no API key for ChatGPT.',
    });
  });

  test('rejects a body over the size limit', () async {
    final oversized = jsonEncode({
      'provider': 'claude',
      'messages': [
        {'role': 'user', 'content': 'a' * (maxBodyBytes + 1)},
      ],
    });

    final response = await send(
      idleHandler(),
      'POST',
      '/chat',
      body: oversized,
    );

    expect(response.statusCode, 413);
    expect(response.headers['access-control-allow-origin'], '*');
    expect(jsonDecode(await response.readAsString()), {'error': isA<String>()});
  });

  test('stops reading a streamed body once it passes the limit', () async {
    // No content-length, as with a chunked upload.
    final chunk = List.filled(64 * 1024, 0x61);
    final body = Stream.fromIterable(
      List.filled(maxBodyBytes ~/ chunk.length + 1, chunk),
    );

    final response = await idleHandler()(
      Request('POST', Uri.parse('http://localhost/chat'), body: body),
    );

    expect(response.statusCode, 413);
  });

  group('POST /chat rejects', () {
    final badRequests = [
      ('invalid JSON', 'not json'),
      ('a body that is not an object', '[1, 2, 3]'),
      ('a missing provider', '{"messages":[{"role":"user","content":"Hi"}]}'),
      (
        'an unconfigured provider',
        '{"provider":"gemini","messages":[{"role":"user","content":"Hi"}]}',
      ),
      (
        'an unknown provider',
        '{"provider":"llama","messages":[{"role":"user","content":"Hi"}]}',
      ),
      ('an empty conversation', '{"provider":"claude","messages":[]}'),
      (
        'an unknown role',
        '{"provider":"claude","messages":[{"role":"system","content":"Hi"}]}',
      ),
      (
        'a blank message',
        '{"provider":"claude","messages":[{"role":"user","content":"  "}]}',
      ),
      (
        'a conversation that ends with the assistant',
        '{"provider":"claude","messages":['
            '{"role":"user","content":"Hi"},'
            '{"role":"assistant","content":"Hello"}]}',
      ),
      (
        'a conversation with too many messages',
        jsonEncode({
          'provider': 'claude',
          'messages': [
            for (var i = 0; i <= ChatRequest.maxMessages; i++)
              {'role': 'user', 'content': 'Hi'},
          ],
        }),
      ),
    ];

    for (final (description, body) in badRequests) {
      test(description, () async {
        final response = await send(idleHandler(), 'POST', '/chat', body: body);

        expect(response.statusCode, 400);
        expect(response.headers['access-control-allow-origin'], '*');
        expect(jsonDecode(await response.readAsString()), {
          'error': isA<String>(),
        });
      });
    }
  });
}
