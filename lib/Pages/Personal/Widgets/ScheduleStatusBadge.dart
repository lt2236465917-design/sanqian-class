import 'package:flutter/material.dart';

/// A text label carries the status even when colors cannot be distinguished.
class ScheduleStatusBadge extends StatelessWidget {
  final String label;
  final bool emphasized;
  const ScheduleStatusBadge(this.label, {super.key, this.emphasized = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: emphasized
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: emphasized
              ? colors.onPrimaryContainer
              : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}
