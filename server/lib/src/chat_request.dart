import 'dart:convert';

import 'providers/chat_provider.dart';

/// A validated `POST /chat` body.
class ChatRequest {
  const ChatRequest({
    required this.provider,
    required this.messages,
    this.system,
  });

  /// Parses and validates a raw request body.
  ///
  /// Throws a [FormatException] whose message is safe to send back to the
  /// caller.
  factory ChatRequest.parse(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      throw const FormatException('The request body must be valid JSON.');
    }
    if (json is! Map<String, dynamic>) {
      throw const FormatException('The request body must be a JSON object.');
    }

    final provider = json['provider'];
    if (provider is! String || provider.isEmpty) {
      throw const FormatException('"provider" is required.');
    }

    final rawMessages = json['messages'];
    if (rawMessages is! List<dynamic> || rawMessages.isEmpty) {
      throw const FormatException('"messages" must be a non-empty list.');
    }
    if (rawMessages.length > maxMessages) {
      throw const FormatException(
        'A conversation can have at most $maxMessages messages. Clear the '
        'chat to start a new one.',
      );
    }
    final messages = [for (final raw in rawMessages) _parseTurn(raw)];
    if (messages.last.role != ChatRole.user) {
      throw const FormatException('The last message must be from the user.');
    }

    final system = json['system'];
    if (system is! String?) {
      throw const FormatException('"system" must be a string.');
    }

    return ChatRequest(
      provider: provider,
      messages: messages,
      system: system == null || system.trim().isEmpty ? null : system,
    );
  }

  /// Longest conversation the proxy forwards, which bounds the cost of a
  /// single request.
  static const maxMessages = 100;

  /// Provider id: `openai`, `gemini` or `claude`.
  final String provider;
  final List<ChatTurn> messages;

  /// Optional system prompt. Replaces the server's default when present,
  /// unless the server is configured to ignore client prompts.
  final String? system;

  static ChatTurn _parseTurn(Object? raw) {
    if (raw case {'role': final String role, 'content': final String content}) {
      final chatRole = ChatRole.values.asNameMap()[role];
      if (chatRole != null && content.trim().isNotEmpty) {
        return ChatTurn(role: chatRole, content: content);
      }
    }
    throw const FormatException(
      'Each message needs a "role" of "user" or "assistant" and non-empty '
      '"content".',
    );
  }
}
