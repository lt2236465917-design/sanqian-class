import 'package:flutter/material.dart';

/// Shared information hierarchy for schedule, import and preferences.
class ScheduleIntro extends StatelessWidget {
  final IconData icon;
  final String eyebrow, title, description;
  const ScheduleIntro({
    super.key,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryContainer.withValues(alpha: .72),
            colors.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  eyebrow,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class ScheduleSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  const ScheduleSection(this.title, {super.key, this.subtitle});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    ),
  );
}

class ScheduleActionTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  const ScheduleActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: .6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, size: 22, color: colors.primary),
      ),
      title: Text(title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(subtitle),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
      enabled: onTap != null,
    );
  }
}

class ScheduleNotice extends StatelessWidget {
  final String text;
  final bool error;
  const ScheduleNotice(this.text, {super.key, this.error = false});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: error ? colors.errorContainer : colors.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          text,
          style: TextStyle(
            height: 1.5,
            color: error ? colors.onErrorContainer : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class ImportJourney extends StatelessWidget {
  final int step;
  const ImportJourney({super.key, required this.step});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in ['选择来源', '识别课表', '核对保存'].asMap().entries)
            Semantics(
              selected: item.key == step,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: item.key == step
                      ? colors.primaryContainer
                      : colors.surface,
                ),
                child: Text(
                  '${item.key + 1}  ${item.value}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: item.key == step
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: item.key == step
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
