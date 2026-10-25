import 'dart:async';

import 'package:ai_chat_starter/features/chat/application/chat_controller.dart';
import 'package:ai_chat_starter/features/chat/data/ai_provider.dart';
import 'package:ai_chat_starter/features/chat/data/chat_exception.dart';
import 'package:ai_chat_starter/features/chat/data/chat_message.dart';
import 'package:ai_chat_starter/features/chat/data/chat_repository.dart';
import 'package:ai_chat_starter/features/chat/data/demo_chat_repository.dart';
import 'package:ai_chat_starter/features/chat/data/proxy_chat_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hands out one reply stream per request and lets the test drive it.
class FakeChatRepository implements ChatRepository {
  final requests = <({AiProvider provider, List<ChatMessage> history})>[];
  var cancelled = false;
  late StreamController<String> _reply;

  @override
  Stream<String> streamReply(AiProvider provider, List<ChatMessage> history) {
    requests.add((provider: provider, history: history));
    _reply = StreamController<String>(
      onCancel: () {
        cancelled = true;
      },
    );
    return _reply.stream;
  }

  void emit(String text) => _reply.add(text);

  void fail(Object error) => _reply.addError(error);

  void finish() => _reply.close();
}

void main() {
  late FakeChatRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeChatRepository();
    container = ProviderContainer.test(
      overrides: [
        demoChatRepositoryProvider.overrideWithValue(repository),
        proxyChatRepositoryProvider.overrideWithValue(repository),
      ],
    );
  });

  ChatController controller() =>
      container.read(chatControllerProvider.notifier);
  ChatState state() => container.read(chatControllerProvider);
  List<String> texts() => [for (final m in state().messages) m.text];

  // Stream events are delivered asynchronously, so let them through.
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('accumulates streamed text in a single assistant message', () async {
    controller().send('Hello');

    expect(state().messages.map((m) => m.role), [
      MessageRole.user,
      MessageRole.assistant,
    ]);
    expect(state().messages.last.status, MessageStatus.sending);
    expect(state().isStreaming, isTrue);

    repository
      ..emit('Hi')
      ..emit(' there');
    await flush();

    expect(state().messages.last.text, 'Hi there');
    expect(state().messages.last.status, MessageStatus.streaming);

    repository.finish();
    await flush();

    expect(state().messages.last.status, MessageStatus.done);
    expect(state().isStreaming, isFalse);
  });

  test('trims input and ignores blank messages', () {
    controller()
      ..send('   ')
      ..send('\n');
    expect(state().messages, isEmpty);

    controller().send('  Hello  ');
    expect(state().messages.first.text, 'Hello');
  });

  test('does not send again while a reply is streaming', () {
    controller()
      ..send('First')
      ..send('Second');

    expect(repository.requests, hasLength(1));
    expect(texts(), ['First', '']);
  });

  test('marks a failed reply and retries with the same history', () async {
    controller().send('Hello');
    repository.fail(const ChatException('Server unavailable'));
    await flush();

    final failed = state().messages.last;
    expect(failed.status, MessageStatus.error);
    expect(failed.errorMessage, 'Server unavailable');
    expect(state().isStreaming, isFalse);

    controller().retryLast();

    expect(repository.requests, hasLength(2));
    expect(repository.requests.last.history.map((m) => m.text), ['Hello']);
    expect(state().messages.last.status, MessageStatus.sending);

    repository
      ..emit('Back online')
      ..finish();
    await flush();

    expect(texts(), ['Hello', 'Back online']);
    expect(state().messages.last.status, MessageStatus.done);
  });

  test('shows a generic message for unexpected errors', () async {
    final logs = <String?>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    addTearDown(() => debugPrint = originalDebugPrint);

    controller().send('Hello');
    repository.fail(StateError('boom'));
    await flush();

    expect(
      state().messages.last.errorMessage,
      'Something went wrong. Please try again.',
    );
    expect(logs.single, contains('boom'));
  });

  test('reports an empty reply as an error', () async {
    controller().send('Hello');
    repository.finish();
    await flush();

    expect(state().messages.last.status, MessageStatus.error);
  });

  test('leaves failed replies out of the next request', () async {
    controller().send('First');
    repository.fail(const ChatException('Nope'));
    await flush();

    controller().send('Second');

    expect(repository.requests.last.history.map((m) => m.text), [
      'First',
      'Second',
    ]);
  });

  test('stop cancels the stream and keeps the partial reply', () async {
    controller().send('Hello');
    repository.emit('Partial');
    await flush();

    controller().stop();

    expect(repository.cancelled, isTrue);
    expect(state().messages.last.text, 'Partial');
    expect(state().messages.last.status, MessageStatus.done);
    expect(state().isStreaming, isFalse);
  });

  test('stop before the first token drops the empty reply', () {
    controller()
      ..send('Hello')
      ..stop();

    expect(repository.cancelled, isTrue);
    expect(texts(), ['Hello']);
    expect(state().isStreaming, isFalse);
  });

  test('never keeps a blank reply as history', () async {
    controller().send('First');
    repository.emit('\n\n');
    await flush();
    controller().stop();

    expect(texts(), ['First']);

    controller().send('Second');
    repository
      ..emit('  ')
      ..finish();
    await flush();

    expect(state().messages.last.status, MessageStatus.error);

    controller().send('Third');
    expect(repository.requests.last.history.map((m) => m.text), [
      'First',
      'Second',
      'Third',
    ]);
  });

  test('clear empties the chat and cancels the reply', () {
    controller()
      ..send('Hello')
      ..clear();

    expect(state().messages, isEmpty);
    expect(repository.cancelled, isTrue);
  });

  test('cancels the reply when the provider is disposed', () {
    controller().send('Hello');
    container.dispose();

    expect(repository.cancelled, isTrue);
  });

  test('asks the selected provider', () {
    controller()
      ..selectProvider(AiProvider.claude)
      ..send('Hello');

    expect(repository.requests.single.provider, AiProvider.claude);
  });
}
