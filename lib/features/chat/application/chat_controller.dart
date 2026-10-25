import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ai_provider.dart';
import '../data/chat_exception.dart';
import '../data/chat_message.dart';
import '../data/chat_repository.dart';
import '../data/demo_chat_repository.dart';
import '../data/proxy_chat_repository.dart';

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);

/// Everything the chat screen needs to render.
@immutable
class ChatState {
  const ChatState({this.messages = const [], this.provider = AiProvider.demo});

  final List<ChatMessage> messages;
  final AiProvider provider;

  /// Whether an assistant reply is in progress.
  bool get isStreaming => messages.lastOrNull?.isPending ?? false;

  ChatState copyWith({List<ChatMessage>? messages, AiProvider? provider}) {
    return ChatState(
      messages: messages ?? this.messages,
      provider: provider ?? this.provider,
    );
  }
}

/// Owns the conversation: sends prompts, streams replies into the last
/// message and handles stop, retry and clear.
class ChatController extends Notifier<ChatState> {
  StreamSubscription<String>? _replySubscription;
  var _nextId = 0;

  @override
  ChatState build() {
    ref.onDispose(_cancelReply);
    return const ChatState();
  }

  void selectProvider(AiProvider provider) {
    state = state.copyWith(provider: provider);
  }

  /// Sends [text] as a user message. Ignored if blank or while a reply is
  /// still streaming.
  void send(String text) {
    final prompt = text.trim();
    if (prompt.isEmpty || state.isStreaming) return;

    _append(ChatMessage(id: _newId(), role: MessageRole.user, text: prompt));
    _requestReply();
  }

  /// Stops the current reply and keeps whatever text already arrived.
  void stop() {
    if (!state.isStreaming) return;
    _cancelReply();

    // A blank reply would be rejected by the proxy as history, so drop it.
    final reply = state.messages.last;
    if (reply.text.trim().isEmpty) {
      _removeLast();
    } else {
      _replaceLast(reply.copyWith(status: MessageStatus.done));
    }
  }

  /// Asks again for the latest reply, if it failed.
  void retryLast() {
    if (state.messages.lastOrNull?.status != MessageStatus.error) return;
    _removeLast();
    _requestReply();
  }

  void clear() {
    _cancelReply();
    state = state.copyWith(messages: const []);
  }

  void _requestReply() {
    // Failed replies add nothing useful to the model's context.
    final history = [
      for (final message in state.messages)
        if (message.status == MessageStatus.done) message,
    ];

    _append(
      ChatMessage(
        id: _newId(),
        role: MessageRole.assistant,
        text: '',
        status: MessageStatus.sending,
      ),
    );

    final provider = state.provider;
    final replies = _repositoryFor(provider).streamReply(provider, history);
    _replySubscription = replies.listen(
      _onDelta,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: true,
    );
  }

  ChatRepository _repositoryFor(AiProvider provider) {
    return ref.read(
      provider.isDemo
          ? demoChatRepositoryProvider
          : proxyChatRepositoryProvider,
    );
  }

  void _onDelta(String delta) {
    final reply = state.messages.last;
    _replaceLast(
      reply.copyWith(text: reply.text + delta, status: MessageStatus.streaming),
    );
  }

  void _onDone() {
    _replySubscription = null;
    final reply = state.messages.last;
    _replaceLast(
      reply.text.trim().isEmpty
          ? reply.copyWith(
              status: MessageStatus.error,
              errorMessage: 'The model returned an empty reply.',
            )
          : reply.copyWith(status: MessageStatus.done),
    );
  }

  void _onError(Object error, StackTrace stackTrace) {
    _replySubscription = null;

    final String message;
    if (error is ChatException) {
      message = error.message;
    } else {
      debugPrint('Unexpected chat error: $error\n$stackTrace');
      message = 'Something went wrong. Please try again.';
    }

    _replaceLast(
      state.messages.last.copyWith(
        status: MessageStatus.error,
        errorMessage: message,
      ),
    );
  }

  void _cancelReply() {
    _replySubscription?.cancel();
    _replySubscription = null;
  }

  String _newId() => 'msg-${_nextId++}';

  void _append(ChatMessage message) {
    state = state.copyWith(messages: [...state.messages, message]);
  }

  void _removeLast() {
    final messages = state.messages;
    state = state.copyWith(messages: messages.sublist(0, messages.length - 1));
  }

  void _replaceLast(ChatMessage message) {
    final messages = state.messages;
    state = state.copyWith(
      messages: [...messages.sublist(0, messages.length - 1), message],
    );
  }
}
