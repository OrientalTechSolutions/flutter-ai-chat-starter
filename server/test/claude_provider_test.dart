import 'package:chat_proxy/chat_proxy.dart';
import 'package:test/test.dart';

import 'fake_upstream.dart';

// A sample stream in the Messages API's documented format, trimmed. It
// includes a thinking block and a ping, both of which must be ignored.
const _reply = '''
event: message_start
data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5-5","content":[],"stop_reason":null,"usage":{"input_tokens":12,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"c2lnbmF0dXJl"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

event: ping
data: {"type":"ping"}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" there"}}

event: content_block_stop
data: {"type":"content_block_stop","index":1}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":9}}

event: message_stop
data: {"type":"message_stop"}

''';

void main() {
  const history = [ChatTurn(role: ChatRole.user, content: 'Hi')];

  ClaudeProvider providerFor(
    String body, {
    int statusCode = 200,
    void Function(SentRequest sent)? onRequest,
  }) {
    return ClaudeProvider(
      apiKey: 'test-key',
      model: 'claude-test',
      maxTokens: 1024,
      client: fakeUpstream(body, statusCode: statusCode, onRequest: onRequest),
    );
  }

  test('streams only text deltas and stops at message_stop', () async {
    final deltas = await providerFor(_reply).stream(history).toList();

    expect(deltas, ['Hello', ' there']);
  });

  test('sends the required headers and a top-level system prompt', () async {
    late SentRequest sent;
    final provider = providerFor(
      _reply,
      onRequest: (request) => sent = request,
    );

    await provider.stream(history, system: 'Be brief.').drain<void>();

    expect(
      sent.request.url,
      Uri.parse('https://api.anthropic.com/v1/messages'),
    );
    expect(sent.request.headers['x-api-key'], 'test-key');
    expect(sent.request.headers['anthropic-version'], '2026-10-21');
    expect(sent.json, {
      'model': 'claude-test',
      'max_tokens': 1024,
      'stream': true,
      'fallbacks': 'default',
      'system': 'Be brief.',
      'messages': [
        {'role': 'user', 'content': 'Hi'},
      ],
    });
  });

  test('reports a refusal', () async {
    final provider = providerFor(
      'data: {"type":"message_start","message":{"id":"msg_1"}}\n\n'
      'data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}\n\n'
      'data: {"type":"message_stop"}\n\n',
    );

    await expectLater(
      provider.stream(history).toList(),
      throwsA(
        isA<ProviderException>().having(
          (e) => e.message,
          'message',
          contains('declined'),
        ),
      ),
    );
  });

  test('turns an error event into a friendly message', () async {
    final provider = providerFor(
      'event: error\n'
      'data: {"type":"error","error":{"type":"overloaded_error",'
      '"message":"Overloaded"}}\n\n',
    );

    await expectLater(
      provider.stream(history).toList(),
      throwsA(
        isA<ProviderException>().having(
          (e) => e.message,
          'message',
          'Claude is overloaded right now. Try again shortly.',
        ),
      ),
    );
  });

  test('maps HTTP errors without leaking the upstream body', () async {
    final provider = providerFor(
      '{"type":"error","error":{"type":"authentication_error",'
      '"message":"invalid x-api-key"}}',
      statusCode: 401,
    );

    await expectLater(
      provider.stream(history).toList(),
      throwsA(
        isA<ProviderException>()
            .having(
              (e) => e.message,
              'message',
              allOf(contains('API key'), isNot(contains('invalid x-api-key'))),
            )
            // The upstream reason is kept for the server log only.
            .having(
              (e) => '${e.cause}',
              'cause',
              allOf(contains('401'), contains('invalid x-api-key')),
            ),
      ),
    );
  });
}
