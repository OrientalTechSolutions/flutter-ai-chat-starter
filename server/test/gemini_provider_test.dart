import 'package:chat_proxy/chat_proxy.dart';
import 'package:test/test.dart';

import 'fake_upstream.dart';

// A sample stream in the documented streamGenerateContent (alt=sse) format,
// trimmed. Gemini separates events with CRLF, which the parser has to cope
// with.
final _reply =
    '''
data: {"candidates":[{"content":{"parts":[{"text":"Hello"}],"role":"model"},"index":0}],"usageMetadata":{"promptTokenCount":3,"candidatesTokenCount":1,"totalTokenCount":4},"modelVersion":"gemini-3.8-flash"}

data: {"candidates":[{"content":{"parts":[{"text":" there"}],"role":"model"},"finishReason":"STOP","index":0}],"usageMetadata":{"promptTokenCount":3,"candidatesTokenCount":2,"totalTokenCount":5},"modelVersion":"gemini-3.8-flash"}

'''
        .replaceAll('\n', '\r\n');

void main() {
  const history = [
    ChatTurn(role: ChatRole.user, content: 'Hi'),
    ChatTurn(role: ChatRole.assistant, content: 'Hello! How can I help?'),
    ChatTurn(role: ChatRole.user, content: 'Say hello again'),
  ];

  GeminiProvider providerFor(
    String body, {
    int statusCode = 200,
    void Function(SentRequest sent)? onRequest,
  }) {
    return GeminiProvider(
      apiKey: 'test-key',
      model: 'gemini-test',
      client: fakeUpstream(body, statusCode: statusCode, onRequest: onRequest),
    );
  }

  test('streams text and stops at the finish reason', () async {
    final deltas = await providerFor(_reply).stream(history).toList();

    expect(deltas, ['Hello', ' there']);
  });

  test('maps roles, adds the system instruction and keeps the key out of '
      'the URL', () async {
    late SentRequest sent;
    final provider = providerFor(
      _reply,
      onRequest: (request) => sent = request,
    );

    await provider.stream(history, system: 'Be brief.').drain<void>();

    expect(
      sent.request.url.path,
      '/v1beta/models/gemini-test:streamGenerateContent',
    );
    expect(sent.request.url.queryParameters, {'alt': 'sse'});
    expect(sent.request.headers['x-goog-api-key'], 'test-key');
    expect(sent.json, {
      'systemInstruction': {
        'parts': [
          {'text': 'Be brief.'},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': 'Hi'},
          ],
        },
        {
          'role': 'model',
          'parts': [
            {'text': 'Hello! How can I help?'},
          ],
        },
        {
          'role': 'user',
          'parts': [
            {'text': 'Say hello again'},
          ],
        },
      ],
    });
  });

  test('skips thought parts', () async {
    final provider = providerFor(
      'data: {"candidates":[{"content":{"parts":['
      '{"text":"Planning the answer","thought":true},{"text":"Hi"}'
      ']},"finishReason":"STOP"}]}\n\n',
    );

    expect(await provider.stream(history).toList(), ['Hi']);
  });

  test('keeps the text when the output limit ends the reply', () async {
    for (final reason in ['MAX_TOKENS', 'CONTINUATION']) {
      final provider = providerFor(
        'data: {"candidates":[{"content":{"parts":[{"text":"Hel"}]}}]}\n\n'
        'data: {"candidates":[{"content":{"parts":[{"text":"lo"}]},'
        '"finishReason":"$reason"}]}\n\n',
      );

      expect(await provider.stream(history).toList(), ['Hel', 'lo']);
    }
  });

  test('reports a blocked prompt', () async {
    final provider = providerFor(
      'data: {"promptFeedback":{"blockReason":"SAFETY"}}\n\n',
    );

    await expectLater(
      provider.stream(history).toList(),
      throwsA(
        isA<ProviderException>().having(
          (e) => e.message,
          'message',
          contains('blocked'),
        ),
      ),
    );
  });

  test('reports a reply stopped for safety', () async {
    final provider = providerFor(
      'data: {"candidates":[{"content":{"parts":[{"text":"Hel"}]}}]}\n\n'
      'data: {"candidates":[{"finishReason":"SAFETY"}]}\n\n',
    );

    await expectLater(
      provider.stream(history),
      emitsInOrder(['Hel', emitsError(isA<ProviderException>())]),
    );
  });

  test('maps HTTP errors to a safe message', () async {
    final provider = providerFor(
      '{"error":{"code":400,"message":"API key not valid."}}',
      statusCode: 403,
    );

    await expectLater(
      provider.stream(history).toList(),
      throwsA(
        isA<ProviderException>()
            .having(
              (e) => e.message,
              'message',
              'Gemini rejected the API key set on the server.',
            )
            .having((e) => '${e.cause}', 'cause', contains('403')),
      ),
    );
  });
}
