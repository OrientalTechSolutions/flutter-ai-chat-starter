import 'dart:convert';

import 'package:http/http.dart' as http;

import '../sse.dart';
import 'chat_provider.dart';

/// Streams replies from the Anthropic Messages API.
class ClaudeProvider implements ChatProvider {
  ClaudeProvider({
    required String apiKey,
    required this.model,
    this.maxTokens = 64000,
    http.Client? client,
  }) : _apiKey = apiKey,
       _client = client ?? http.Client();

  static final _endpoint = Uri.parse('https://api.anthropic.com/v1/messages');

  final String _apiKey;
  final String model;

  /// Upper bound on reply length. Required by the API; streaming keeps a
  /// generous limit safe from request timeouts.
  final int maxTokens;
  final http.Client _client;

  @override
  String get name => 'Claude';

  @override
  Stream<String> stream(List<ChatTurn> messages, {String? system}) async* {
    final request = http.Request('POST', _endpoint)
      ..headers.addAll({
        'x-api-key': _apiKey,
        'anthropic-version': '2026-10-21',
        // Opts in to the server-side fallback below.
        'anthropic-beta': 'server-side-fallback-2026-07-01',
        'content-type': 'application/json',
      })
      ..body = jsonEncode({
        'model': model,
        'max_tokens': maxTokens,
        'stream': true,
        // If a safety classifier declines the request, Anthropic retries it
        // on its recommended fallback model within the same stream.
        'fallbacks': 'default',
        'system': ?system,
        'messages': [
          for (final turn in messages)
            {'role': turn.role.name, 'content': turn.content},
        ],
      });

    final body = await sendStreamingRequest(_client, request, provider: name);
    await for (final data in readSseData(body)) {
      switch (jsonDecode(data)) {
        case {
          'type': 'content_block_delta',
          'delta': {'type': 'text_delta', 'text': final String text},
        }:
          yield text;
        case {'type': 'message_delta', 'delta': {'stop_reason': 'refusal'}}:
          throw const ProviderException(
            'Claude declined to answer this request.',
          );
        case {'type': 'message_stop'}:
          return;
        case {'type': 'error', 'error': {'type': final String type}}:
          throw ProviderException(_errorMessage(type), cause: data);
      }
    }
    throw const ProviderException('Claude ended the reply early.');
  }
}

String _errorMessage(String errorType) => switch (errorType) {
  'overloaded_error' => 'Claude is overloaded right now. Try again shortly.',
  'rate_limit_error' => 'Claude is rate limiting requests. Try again shortly.',
  _ => 'Claude stopped the reply with an error.',
};
