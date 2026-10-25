import 'dart:async';

import 'package:chat_proxy/chat_proxy.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('sendStreamingRequest', () {
    const shortTimeout = Duration(milliseconds: 50);

    http.Request newRequest() =>
        http.Request('POST', Uri.parse('https://upstream.test/stream'));

    Matcher providerException(String message) =>
        isA<ProviderException>().having((e) => e.message, 'message', message);

    test('fails when the upstream does not answer', () async {
      final client = MockClient.streaming(
        (request, body) => Completer<http.StreamedResponse>().future,
      );

      await expectLater(
        sendStreamingRequest(
          client,
          newRequest(),
          provider: 'Test',
          responseTimeout: shortTimeout,
        ),
        throwsA(providerException('Test did not respond in time.')),
      );
    });

    test('fails when the upstream stops sending mid-reply', () async {
      final stalledBody = StreamController<List<int>>();
      addTearDown(stalledBody.close);
      final client = MockClient.streaming(
        (request, body) async => http.StreamedResponse(stalledBody.stream, 200),
      );

      final body = await sendStreamingRequest(
        client,
        newRequest(),
        provider: 'Test',
        idleTimeout: shortTimeout,
      );

      await expectLater(
        body.toList(),
        throwsA(providerException('Test stopped responding. Try again.')),
      );
    });

    test('fails when the upstream cannot be reached', () async {
      final client = MockClient.streaming(
        (request, body) => throw http.ClientException('Connection refused'),
      );

      await expectLater(
        sendStreamingRequest(client, newRequest(), provider: 'Test'),
        throwsA(providerException('Could not reach Test.')),
      );
    });
  });
}
