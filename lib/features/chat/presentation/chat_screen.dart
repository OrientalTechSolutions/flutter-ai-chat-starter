import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/chat_controller.dart';
import '../data/chat_message.dart';
import 'widgets/chat_input.dart';
import 'widgets/empty_state.dart';
import 'widgets/message_bubble.dart';
import 'widgets/provider_selector.dart';

/// Widest the conversation gets on large screens, for comfortable reading.
const _maxContentWidth = 760.0;

/// The chat screen: provider picker, conversation and message composer.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear this chat?'),
        content: const Text(
          'All messages in this conversation will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      ref.read(chatControllerProvider.notifier).clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Bring the newest message into view when one is added, even if the user
    // had scrolled up to read earlier ones.
    ref.listen(
      chatControllerProvider.select((state) => state.messages.length),
      (previous, next) {
        if (next > (previous ?? 0)) _scrollToLatest();
      },
    );

    final state = ref.watch(chatControllerProvider);
    final controller = ref.read(chatControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Chat Starter'),
        actions: [
          IconButton(
            tooltip: 'Clear chat',
            onPressed: state.messages.isEmpty ? null : _confirmClear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _ContentWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: ProviderSelector(
                  selected: state.provider,
                  enabled: !state.isStreaming,
                  onChanged: controller.selectProvider,
                ),
              ),
            ),
            Expanded(
              child: state.messages.isEmpty
                  ? _ContentWidth(
                      child: EmptyState(
                        provider: state.provider,
                        onPromptSelected: controller.send,
                      ),
                    )
                  : _MessageList(
                      messages: state.messages,
                      scrollController: _scrollController,
                      onRetry: controller.retryLast,
                    ),
            ),
            _ContentWidth(
              child: ChatInput(
                isStreaming: state.isStreaming,
                onSend: controller.send,
                onStop: controller.stop,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centres [child] and caps it at [_maxContentWidth].
class _ContentWidth extends StatelessWidget {
  const _ContentWidth({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxContentWidth),
        child: child,
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.scrollController,
    required this.onRetry,
  });

  final List<ChatMessage> messages;
  final ScrollController scrollController;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The list spans the full width so it scrolls from anywhere in the
        // window and its scrollbar sits at the edge. Padding keeps the
        // messages themselves in a readable column.
        final gutter =
            16.0 + math.max(0.0, (constraints.maxWidth - _maxContentWidth) / 2);

        // Reversed, so offset 0 is the bottom and the view stays pinned to
        // the reply as it grows.
        return ListView.builder(
          controller: scrollController,
          reverse: true,
          padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 12),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[messages.length - 1 - index];
            return MessageBubble(
              key: ValueKey(message.id),
              message: message,
              // Only the latest reply can be retried.
              onRetry: index == 0 ? onRetry : null,
            );
          },
        );
      },
    );
  }
}
