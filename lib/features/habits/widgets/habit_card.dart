import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/habit.dart';
import '../../../domain/streaks.dart';
import 'check_in_button.dart';
import 'schedule_summary.dart';
import 'streak_flame.dart';

/// A habit card: emoji badge in the habit's colour, name, schedule summary,
/// streak flame and (optionally) a big check-in button.
///
/// Purely presentational — callers supply the state, which makes it usable
/// for the live preview in the form as well as in lists.
class HabitCard extends StatelessWidget {
  final Habit habit;

  /// `null` hides the flame.
  final StreakInfo? streak;
  final bool completed;

  /// Times-per-week progress (see [weeklyProgress]).
  final ({int done, int target})? weekProgress;
  final VoidCallback? onTap;

  /// Called when the check-in button is tapped; `null` disables it.
  final VoidCallback? onCheckIn;

  /// Whether to show the check-in button at all.
  final bool showCheckIn;

  /// Subdued look (e.g. archived habits).
  final bool dimmed;

  /// Optional key for the check-in button (handy in tests).
  final Key? checkInKey;

  const HabitCard({
    super.key,
    required this.habit,
    this.streak,
    this.completed = false,
    this.weekProgress,
    this.onTap,
    this.onCheckIn,
    this.showCheckIn = true,
    this.dimmed = false,
    this.checkInKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = HabitPalette.fromValue(habit.colorValue);
    final isDark = theme.brightness == Brightness.dark;
    final name = habit.name.trim().isEmpty ? 'Your new habit' : habit.name;

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: completed
            ? Color.alphaBlend(
                color.withValues(alpha: isDark ? 0.22 : 0.12),
                scheme.surface,
              )
            : scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: completed
              ? color.withValues(alpha: 0.6)
              : scheme.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.5),
          width: completed ? 2 : 1,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: color.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 6, color: color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Row(
                      children: [
                        _EmojiBadge(emoji: habit.emoji, color: color),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Texts(card: this, name: name),
                        ),
                        if (showCheckIn) ...[
                          const SizedBox(width: 8),
                          CheckInButton(
                            key: checkInKey,
                            completed: completed,
                            color: color,
                            onPressed: onCheckIn,
                            semanticLabel: completed
                                ? 'Undo check-in for $name'
                                : 'Check in $name',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return dimmed ? Opacity(opacity: 0.6, child: card) : card;
  }
}

class _Texts extends StatelessWidget {
  final HabitCard card;
  final String name;

  const _Texts({required this.card, required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final streak = card.streak;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          scheduleSummaryWithProgress(card.habit.schedule, card.weekProgress),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (streak != null) ...[
          const SizedBox(height: 4),
          StreakFlame(streak: streak.current, unit: streak.unit, size: 14),
        ],
      ],
    );
  }
}

class _EmojiBadge extends StatelessWidget {
  final String emoji;
  final Color color;

  const _EmojiBadge({required this.emoji, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 4),
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 28, height: 1)),
    );
  }
}
