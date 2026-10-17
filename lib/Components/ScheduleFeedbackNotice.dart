import 'package:flutter/material.dart';

/// Non-blocking feedback shared by iOS and Android.
class ScheduleFeedbackNotice {
  static void show(
    BuildContext context,
    String message, {
    double bottomSpacing = 16,
  }) {
    if (!context.mounted) return;
    final colors = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final horizontal = ((media.size.width - 420) / 2).clamp(
      20.0,
      double.infinity,
    );
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(horizontal, 0, horizontal, bottomSpacing),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: colors.primaryContainer,
        elevation: 3,
        duration: Duration(seconds: media.accessibleNavigation ? 8 : 3),
        content: Text(
          message,
          style: TextStyle(color: colors.onPrimaryContainer, height: 1.5),
        ),
      ),
    );
  }
}

/// Persistent errors stay beside the action that can resolve them.
class ScheduleInlineFeedback extends StatelessWidget {
  final String message;
  final VoidCallback? onAction;
  final String? actionLabel;

  const ScheduleInlineFeedback({
    super.key,
    required this.message,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: TextStyle(color: colors.onErrorContainer, height: 1.5),
            ),
            if (actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: colors.onErrorContainer,
                ),
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}
