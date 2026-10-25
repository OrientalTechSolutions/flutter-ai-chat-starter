import 'package:flutter/material.dart';

import '../../data/ai_provider.dart';

/// Shown before the first message, with a few prompts to get started.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.provider,
    required this.onPromptSelected,
  });

  static const suggestions = [
    'Explain Riverpod in one paragraph',
    'How are API keys kept safe?',
    'AI feature ideas for a food app',
    'Welcome text for a fitness app',
  ];

  final AiProvider provider;
  final ValueChanged<String> onPromptSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = provider.isDemo
        ? 'Demo mode answers on device, with no server or API key needed.'
        : 'Messages go to ${provider.displayName} through your chat server.';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'How can I help?',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final prompt in suggestions)
                  ActionChip(
                    label: Text(prompt),
                    onPressed: () => onPromptSelected(prompt),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
