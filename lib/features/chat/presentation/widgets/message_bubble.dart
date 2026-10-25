import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/chat_message.dart';
import 'typing_indicator.dart';

/// One message in the conversation, with copy and retry actions.
class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, this.onRetry});

  final ChatMessage message;

  /// Called by the Retry button on a failed reply. Null hides the button.
  final VoidCallback? onRetry;

  static const _corner = Radius.circular(18);
  static const _tail = Radius.circular(4);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    final failed = message.status == MessageStatus.error;

    final (background, foreground) = switch ((isUser, failed)) {
      (_, true) => (colors.errorContainer, colors.onErrorContainer),
      (true, _) => (colors.primaryContainer, colors.onPrimaryContainer),
      _ => (colors.surfaceContainerHighest, colors.onSurface),
    };

    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        bottom: 4,
        left: isUser ? 48 : 0,
        right: isUser ? 0 : 48,
      ),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Semantics(
            label: isUser ? 'You' : 'Assistant',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.only(
                  topLeft: _corner,
                  topRight: _corner,
                  bottomLeft: isUser ? _corner : _tail,
                  bottomRight: isUser ? _tail : _corner,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: _MessageContent(message: message, color: foreground),
              ),
            ),
          ),
          if (failed && onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          if (!isUser && message.status == MessageStatus.done)
            _CopyButton(text: message.text),
        ],
      ),
    );
  }
}

class _MessageContent extends StatelessWidget {
  const _MessageContent({required this.message, required this.color});

  final ChatMessage message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (message.status == MessageStatus.sending) {
      return const TypingIndicator();
    }

    final textStyle = Theme.of(
      context,
    ).textTheme.bodyLarge?.copyWith(color: color);
    final error = message.errorMessage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.text.isNotEmpty)
          SelectableText(message.text, style: textStyle),
        if (error != null) ...[
          if (message.text.isNotEmpty) const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 18, color: color),
              const SizedBox(width: 6),
              Flexible(child: Text(error, style: textStyle)),
            ],
          ),
        ],
      ],
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Copy',
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      onPressed: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
      },
      icon: const Icon(Icons.copy_rounded),
    );
  }
}
