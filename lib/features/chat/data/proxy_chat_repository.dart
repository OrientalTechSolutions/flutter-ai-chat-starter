import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config.dart';
import 'ai_provider.dart';
import 'chat_exception.dart';
import 'chat_message.dart';
import 'chat_repository.dart';
import 'sse_parser.dart';

final proxyChatRepositoryProvider = Provider<ChatRepository>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return ProxyChatRepository(baseUrl: AppConfig.chatApiUrl, client: client);
});

/// Streams replies through the chat proxy in `/server`, which holds the API
/// keys and talks to the providers.
class ProxyChatRepository implements ChatRepository {
  ProxyChatRepository({required String baseUrl, http.Client? client})
    : _endpoint = Uri.parse('${_withoutTrailingSlash(baseUrl)}/chat'),
      _client = client ?? http.Client();

  final Uri _endpoint;
  final http.Client _client;

  @override
  Stream<String> streamReply(
    AiProvider provider,
    List<ChatMessage> history,
  ) async* {
    assert(!provider.isDemo, 'Demo replies are generated on device.');

    final request = http.Request('POST', _endpoint)
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode({
        'provider': provider.apiId,
        'messages': [
          for (final message in history)
            {'role': message.role.name, 'content': message.text},
        ],
      });

    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } on http.ClientException {
      throw ChatException(
        "Can't reach the chat server at ${_endpoint.origin}. "
        'Check that it is running, or switch to Demo.',
      );
    }

    if (response.statusCode != 200) {
      throw ChatException(await _describeFailure(response));
    }

    try {
      await for (final event in decodeChatEvents(response.stream)) {
        switch (event) {
          case DeltaEvent(:final text):
            yield text;
          case DoneEvent():
            return;
          case ErrorEvent(:final message):
            throw ChatException(message);
        }
      }
    } on http.ClientException {
      throw const ChatException('The connection dropped mid-reply.');
    } on FormatException {
      throw const ChatException(
        'The chat server sent a reply the app could not read.',
      );
    }

    // The body ended without a done event, so the reply is incomplete.
    throw const ChatException('The connection dropped mid-reply.');
  }

  Future<String> _describeFailure(http.StreamedResponse response) async {
    final serverMessage = _errorField(await _readBodyOrEmpty(response));
    if (serverMessage != null) return serverMessage;

    return switch (response.statusCode) {
      404 => 'The chat server has no /chat endpoint. Check CHAT_API_URL.',
      429 => 'Too many requests. Wait a moment and try again.',
      >= 500 => 'The chat server ran into a problem. Try again shortly.',
      final code => 'The chat server rejected the request (HTTP $code).',
    };
  }

  /// Reads an error body, or returns an empty string if the connection drops
  /// while reading it, so the status code can still explain the failure.
  static Future<String> _readBodyOrEmpty(http.StreamedResponse response) async {
    try {
      return await response.stream.bytesToString();
    } on http.ClientException {
      return '';
    }
  }

  /// Reads the `{"error": "..."}` body the proxy sends with 4xx responses.
  static String? _errorField(String body) {
    try {
      return switch (jsonDecode(body)) {
        {'error': final String message} => message,
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }

  static String _withoutTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
