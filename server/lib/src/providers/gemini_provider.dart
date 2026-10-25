import 'dart:convert';

import 'package:http/http.dart' as http;

import '../sse.dart';
import 'chat_provider.dart';

/// Streams replies from the Gemini API's `streamGenerateContent` method.
class GeminiProvider implements ChatProvider {
  GeminiProvider({
    required String apiKey,
    required this.model,
    http.Client? client,
  }) : _apiKey = apiKey,
       _client = client ?? http.Client();

  final String _apiKey;
  final String model;
  final http.Client _client;

  @override
  String get name => 'Gemini';

  @override
  Stream<String> stream(List<ChatTurn> messages, {String? system}) async* {
    final endpoint = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$model:streamGenerateContent',
      {'alt': 'sse'},
    );

    // The key goes in a header rather than the query string, so it never
    // ends up in a logged URL.
    final request = http.Request('POST', endpoint)
      ..headers.addAll({
        'x-goog-api-key': _apiKey,
        'content-type': 'application/json',
      })
      ..body = jsonEncode({
        if (system != null)
          'systemInstruction': {
            'parts': [
              {'text': system},
            ],
          },
        'contents': [
          for (final turn in messages)
            {
              'role': turn.role == ChatRole.user ? 'user' : 'model',
              'parts': [
                {'text': turn.content},
              ],
            },
        ],
      });

    final body = await sendStreamingRequest(_client, request, provider: name);
    await for (final data in readSseData(body)) {
      switch (jsonDecode(data)) {
        case {'promptFeedback': {'blockReason': final String reason}}:
          throw ProviderException('Gemini blocked this prompt ($reason).');
        case {'error': _}:
          throw const ProviderException(
            'Gemini stopped the reply with an error.',
          );
        case {'candidates': [final Map<String, dynamic> candidate, ...]}:
          final text = _candidateText(candidate);
          if (text.isNotEmpty) yield text;

          // MAX_TOKENS and CONTINUATION both mean the output limit was hit.
          // Like the other providers, keep the text that arrived.
          final finishReason = candidate['finishReason'];
          if (_normalFinishReasons.contains(finishReason)) return;
          if (finishReason != null) {
            throw ProviderException(
              'Gemini stopped the reply early ($finishReason).',
            );
          }
      }
    }
    throw const ProviderException('Gemini ended the reply early.');
  }
}

const _normalFinishReasons = {'STOP', 'MAX_TOKENS', 'CONTINUATION'};

/// Joins the text parts of a candidate, skipping thought summaries.
String _candidateText(Map<String, dynamic> candidate) {
  final parts = switch (candidate) {
    {'content': {'parts': final List<dynamic> contentParts}} => contentParts,
    _ => const <dynamic>[],
  };
  return parts
      .whereType<Map<String, dynamic>>()
      .where((part) => part['thought'] != true)
      .map((part) => part['text'])
      .whereType<String>()
      .join();
}
