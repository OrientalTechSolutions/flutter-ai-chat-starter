import 'dart:convert';

import 'package:http/http.dart' as http;

import '../sse.dart';
import 'chat_provider.dart';

/// Streams replies from the OpenAI Chat Completions API.
class OpenAiProvider implements ChatProvider {
  OpenAiProvider({
    required String apiKey,
    required this.model,
    http.Client? client,
  }) : _apiKey = apiKey,
       _client = client ?? http.Client();

  static final _endpoint = Uri.parse(
    'https://api.openai.com/v1/chat/completions',
  );

  final String _apiKey;
  final String model;
  final http.Client _client;

  @override
  String get name => 'OpenAI';

  @override
  Stream<String> stream(List<ChatTurn> messages, {String? system}) async* {
    final request = http.Request('POST', _endpoint)
      ..headers.addAll({
        'authorization': 'Bearer $_apiKey',
        'content-type': 'application/json',
      })
      ..body = jsonEncode({
        'model': model,
        'stream': true,
        'messages': [
          if (system != null) {'role': 'system', 'content': system},
          for (final turn in messages)
            {'role': turn.role.name, 'content': turn.content},
        ],
      });

    final body = await sendStreamingRequest(_client, request, provider: name);
    await for (final data in readSseData(body)) {
      if (data == '[DONE]') return;

      final text = _deltaText(jsonDecode(data));
      if (text != null && text.isNotEmpty) yield text;
    }
    throw const ProviderException('OpenAI ended the reply early.');
  }
}

/// Pulls the text out of one `chat.completion.chunk`.
String? _deltaText(Object? chunk) {
  return switch (chunk) {
    {'error': _} => throw const ProviderException(
      'OpenAI stopped the reply with an error.',
    ),
    {'choices': [{'finish_reason': 'content_filter'}, ...]} =>
      throw const ProviderException('OpenAI filtered this reply.'),
    {'choices': [{'delta': {'content': final String text}}, ...]} => text,
    _ => null,
  };
}
