import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// A rounded stat tile: visual on top, big value, small label.
class StatTile extends StatelessWidget {
  final Widget visual;
  final String value;
  final String label;
  final Color accent;

  const StatTile({
    super.key,
    required this.visual,
    required this.value,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.45 : 0.25),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          SizedBox(height: 48, child: Center(child: visual)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
