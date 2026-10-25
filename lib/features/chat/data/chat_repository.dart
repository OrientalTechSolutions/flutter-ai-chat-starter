import 'ai_provider.dart';
import 'chat_message.dart';

/// Source of assistant replies.
abstract interface class ChatRepository {
  /// Streams the reply to [history] in chunks of text.
  ///
  /// [history] ends with the user's latest message. Failures arrive as
  /// `ChatException` errors on the returned stream.
  Stream<String> streamReply(AiProvider provider, List<ChatMessage> history);
}
