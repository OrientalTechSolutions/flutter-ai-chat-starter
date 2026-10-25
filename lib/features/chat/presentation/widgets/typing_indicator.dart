import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Three pulsing dots, shown while waiting for the first token of a reply.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;

    return Semantics(
      label: 'Assistant is typing',
      child: SizedBox(
        height: 24,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              _Dot(animation: _controller, lag: i * 0.2, color: color),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.animation, required this.lag, required this.color});

  final Animation<double> animation;

  /// How far, as a fraction of one cycle, this dot trails the first.
  final double lag;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final phase = (animation.value - lag) % 1.0;
        return Opacity(
          opacity: 0.3 + 0.7 * math.sin(phase * math.pi),
          child: child,
        );
      },
      child: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
