import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/streaks.dart';

/// "5 days", "1 day", "3 wks", "1 wk".
String streakLabel(int streak, StreakUnit unit) => switch (unit) {
  StreakUnit.days => '$streak ${streak == 1 ? 'day' : 'days'}',
  StreakUnit.weeks => '$streak ${streak == 1 ? 'wk' : 'wks'}',
};

/// A 🔥 flame that grows and glows brighter with the streak. A zero streak
/// shows a faded flame. Size changes animate (e.g. right after a check-in).
class StreakFlame extends StatelessWidget {
  final int streak;
  final StreakUnit unit;

  /// Flame size at streak 0; it grows up to ~1.8× this.
  final double size;
  final bool showLabel;

  const StreakFlame({
    super.key,
    required this.streak,
    this.unit = StreakUnit.days,
    this.size = 18,
    this.showLabel = true,
  });

  /// 0 (cold) … 1 (blazing), reached at 30 periods (days) / 12 (weeks).
  double get intensity {
    final full = unit == StreakUnit.weeks ? 12 : 30;
    return (streak / full).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = streak > 0;
    final target = active ? size * (1.1 + 0.7 * intensity) : size;
    final flame = TweenAnimationBuilder<double>(
      tween: Tween(end: target),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutBack,
      builder: (context, s, _) => Container(
        width: s * 1.35,
        height: s * 1.35,
        alignment: Alignment.center,
        decoration: active
            ? BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.flame.withValues(
                      alpha: 0.15 + 0.4 * intensity,
                    ),
                    blurRadius: 6 + 14 * intensity,
                    spreadRadius: 1 + 3 * intensity,
                  ),
                ],
              )
            : null,
        child: Opacity(
          opacity: active ? 1 : 0.3,
          child: Text('🔥', style: TextStyle(fontSize: s, height: 1)),
        ),
      ),
    );
    if (!showLabel) return flame;
    return Semantics(
      label: 'Streak ${streakLabel(streak, unit)}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          flame,
          const SizedBox(width: 4),
          Text(
            streakLabel(streak, unit),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: active
                  ? Color.lerp(AppColors.flame, AppColors.coral, intensity)
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
