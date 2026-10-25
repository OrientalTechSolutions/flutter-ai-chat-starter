import 'package:flutter/material.dart';

import '../../data/ai_provider.dart';

/// Picks which model answers the next message.
class ProviderSelector extends StatelessWidget {
  const ProviderSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final AiProvider selected;
  final ValueChanged<AiProvider> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // Scrolls rather than overflows on very narrow screens.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<AiProvider>(
        showSelectedIcon: false,
        segments: [
          for (final provider in AiProvider.values)
            ButtonSegment(value: provider, label: Text(provider.displayName)),
        ],
        selected: {selected},
        onSelectionChanged: enabled
            ? (selection) => onChanged(selection.single)
            : null,
      ),
    );
  }
}
