import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The message composer.
///
/// When a hardware keyboard is attached (web, tablets), Enter sends and
/// Shift+Enter starts a new line. While a reply is streaming the send button
/// turns into a stop button, and typing stays enabled so the next message can
/// be drafted.
class ChatInput extends StatefulWidget {
  const ChatInput({
    super.key,
    required this.isStreaming,
    required this.onSend,
    required this.onStop,
  });

  final bool isStreaming;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isStreaming) return;

    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): _submit,
                const SingleActivator(LogicalKeyboardKey.numpadEnter): _submit,
              },
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Message',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (widget.isStreaming)
            IconButton.filledTonal(
              tooltip: 'Stop generating',
              onPressed: widget.onStop,
              icon: const Icon(Icons.stop_rounded),
            )
          else
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => IconButton.filled(
                tooltip: 'Send message',
                onPressed: _controller.text.trim().isEmpty ? null : _submit,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
            ),
        ],
      ),
    );
  }
}
