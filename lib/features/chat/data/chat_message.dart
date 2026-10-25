import 'package:flutter/foundation.dart';

/// Who wrote a message. The names match the roles in the proxy's contract.
enum MessageRole { user, assistant }

/// Where a message is in its lifecycle.
///
/// User messages are always [done]. Assistant replies start as [sending]
/// while waiting for the first token, become [streaming] once text arrives,
/// and end as [done] or [error].
enum MessageStatus { sending, streaming, done, error }

/// One message in the conversation.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.status = MessageStatus.done,
    this.errorMessage,
  });

  final String id;
  final MessageRole role;
  final String text;
  final MessageStatus status;

  /// Why the reply failed. Only set when [status] is [MessageStatus.error].
  final String? errorMessage;

  bool get isUser => role == MessageRole.user;

  /// Whether the assistant is still producing this message.
  bool get isPending =>
      status == MessageStatus.sending || status == MessageStatus.streaming;

  ChatMessage copyWith({
    String? text,
    MessageStatus? status,
    String? errorMessage,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
