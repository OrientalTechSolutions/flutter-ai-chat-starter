import 'package:chat_proxy/chat_proxy.dart';
import 'package:test/test.dart';

import 'fake_upstream.dart';

// A sample stream in the Chat Completions documented format, trimmed to the
// fields that matter.
const _reply = '''
data: {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

data: {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

data: {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":" there"},"finish_reason":null}]}

data: {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]

''';

void main() {
  const history = [ChatTurn(role: ChatRole.user, content: 'Hi')];

  OpenAiProvider providerFor(
    String body, {
    int statusCode = 200,
    void Function(SentRequest sent)? onRequest,
  }) {
    return OpenAiProvider(
      apiKey: 'test-key',
      model: 'gpt-test',
      client: fakeUpstream(body, statusCode: statusCode, onRequest: onRequest),
    );
  }

  test('streams content deltas and stops at [DONE]', () async {
    final deltas = await providerFor(_reply).stream(history).toList();

    expect(deltas, ['Hello', ' there']);
  });

  test('sends the model, system prompt and history', () async {
    late SentRequest sent;
    final provider = providerFor(
      _reply,
      onRequest: (request) => sent = request,
    );

    await provider.stream(history, system: 'Be brief.').drain<void>();

    expect(
      sent.request.url,
      Uri.parse('https://api.openai.com/v1/chat/completions'),
    );
    expect(sent.request.headers['authorization'], 'Bearer test-key');
    expect(sent.json, {
      'model': 'gpt-test',
      'stream': true,
      'messages': [
        {'role': 'system', 'content': 'Be brief.'},
        {'role': 'user', 'content': 'Hi'},
      ],
    });
  });

  test('maps HTTP errors to a safe message', () async {
    final provider = providerFor(
      '{"error":{"message":"Incorrect API key provided: sk-abc123"}}',
      statusCode: 401,
    );

    await expectLater(
      provider.stream(history).toList(),
      throwsA(
        isA<ProviderException>()
            .having(
              (e) => e.message,
              'message',
              allOf(contains('API key'), isNot(contains('sk-abc123'))),
            )
            .having((e) => '${e.cause}', 'cause', contains('401')),
      ),
    );
  });

  test('reports an error sent mid-stream', () async {
    final provider = providerFor(
      'data: {"choices":[{"index":0,"delta":{"content":"Hel"}}]}\n\n'
      'data: {"error":{"message":"Internal error","type":"server_error"}}\n\n',
    );

    await expectLater(
      provider.stream(history),
      emitsInOrder(['Hel', emitsError(isA<ProviderException>())]),
    );
  });

  test('fails if the stream ends without [DONE]', () async {
    final provider = providerFor(
      'data: {"choices":[{"index":0,"delta":{"content":"Hel"}}]}\n\n',
    );

    await expectLater(
      provider.stream(history),
      emitsInOrder(['Hel', emitsError(isA<ProviderException>())]),
    );
  });
}
