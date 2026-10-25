import 'dart:convert';

import 'package:ai_chat_starter/features/chat/data/ai_provider.dart';
import 'package:ai_chat_starter/features/chat/data/chat_exception.dart';
import 'package:ai_chat_starter/features/chat/data/chat_message.dart';
import 'package:ai_chat_starter/features/chat/data/proxy_chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const history = [ChatMessage(id: '1', role: MessageRole.user, text: 'Hi')];

  ProxyChatRepository repositoryReturning(String body, {int status = 200}) {
    return ProxyChatRepository(
      baseUrl: 'http://proxy.test',
      client: MockClient.streaming(
        (request, bodyStream) async =>
            http.StreamedResponse(Stream.value(utf8.encode(body)), status),
      ),
    );
  }

  Matcher chatException(Object message) =>
      isA<ChatException>().having((e) => e.message, 'message', message);

  test('posts the provider and history to /chat', () async {
    late http.BaseRequest sentRequest;
    late Object? sentBody;
    final repository = ProxyChatRepository(
      baseUrl: 'http://proxy.test/',
      client: MockClient.streaming((request, bodyStream) async {
        sentRequest = request;
        sentBody = jsonDecode(await bodyStream.bytesToString());
        return http.StreamedResponse(
          Stream.value(utf8.encode('data: {"type":"done"}\n\n')),
          200,
        );
      }),
    );

    await repository.streamReply(AiProvider.claude, history).drain<void>();

    expect(sentRequest.method, 'POST');
    expect(sentRequest.url, Uri.parse('http://proxy.test/chat'));
    expect(sentBody, {
      'provider': 'claude',
      'messages': [
        {'role': 'user', 'content': 'Hi'},
      ],
    });
  });

  test('yields text deltas until the done event', () async {
    final repository = repositoryReturning(
      'data: {"type":"delta","text":"Hello"}\n\n'
      'data: {"type":"delta","text":" world"}\n\n'
      'data: {"type":"done"}\n\n',
    );

    final chunks = await repository
        .streamReply(AiProvider.chatGpt, history)
        .toList();

    expect(chunks, ['Hello', ' world']);
  });

  test('turns an error event into a ChatException', () async {
    final repository = repositoryReturning(
      'data: {"type":"delta","text":"Hel"}\n\n'
      'data: {"type":"error","message":"Gemini is having problems."}\n\n',
    );

    await expectLater(
      repository.streamReply(AiProvider.gemini, history),
      emitsInOrder([
        'Hel',
        emitsError(chatException('Gemini is having problems.')),
      ]),
    );
  });

  test('shows the server message for a rejected request', () async {
    final repository = repositoryReturning(
      '{"error":"The chat server has no API key for Gemini."}',
      status: 400,
    );

    await expectLater(
      repository.streamReply(AiProvider.gemini, history).toList(),
      throwsA(chatException('The chat server has no API key for Gemini.')),
    );
  });

  test('falls back to a generic message when the body is not JSON', () async {
    final repository = repositoryReturning('Bad Gateway', status: 502);

    await expectLater(
      repository.streamReply(AiProvider.claude, history).toList(),
      throwsA(chatException(contains('ran into a problem'))),
    );
  });

  test('uses the status code when the error body cannot be read', () async {
    final repository = ProxyChatRepository(
      baseUrl: 'http://proxy.test',
      client: MockClient.streaming(
        (request, bodyStream) async => http.StreamedResponse(
          Stream.error(http.ClientException('Connection reset')),
          503,
        ),
      ),
    );

    await expectLater(
      repository.streamReply(AiProvider.claude, history).toList(),
      throwsA(chatException(contains('ran into a problem'))),
    );
  });

  test('explains when the server cannot be reached', () async {
    final repository = ProxyChatRepository(
      baseUrl: 'http://proxy.test',
      client: MockClient.streaming(
        (request, bodyStream) async =>
            throw http.ClientException('Connection refused'),
      ),
    );

    await expectLater(
      repository.streamReply(AiProvider.claude, history).toList(),
      throwsA(chatException(contains("Can't reach the chat server"))),
    );
  });

  test('fails when the stream ends without a done event', () async {
    final repository = repositoryReturning(
      'data: {"type":"delta","text":"Partial"}\n\n',
    );

    await expectLater(
      repository.streamReply(AiProvider.claude, history),
      emitsInOrder(['Partial', emitsError(chatException(contains('dropped')))]),
    );
  });
}
