import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/habit.dart';
import '../schedule_summary.dart';

/// Big emoji in a colour-tinted circle, the name, schedule and reminder.
class HabitHeader extends StatelessWidget {
  final Habit habit;

  const HabitHeader({super.key, required this.habit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = HabitPalette.fromValue(habit.colorValue);
    final reminder = habit.reminderTime;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: isDark ? 0.32 : 0.22),
            color.withValues(alpha: isDark ? 0.12 : 0.06),
          ],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: isDark ? 0.4 : 0.28),
              border: Border.all(color: color, width: 3),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(habit.emoji, style: const TextStyle(fontSize: 52)),
          ),
          const SizedBox(height: 14),
          Text(
            habit.name,
            key: const ValueKey('habit-name'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(
                key: const ValueKey('habit-schedule'),
                icon: Icons.event_repeat_rounded,
                text: scheduleSummary(habit.schedule),
                color: color,
              ),
              if (reminder != null)
                _Pill(
                  key: const ValueKey('habit-reminder'),
                  icon: Icons.alarm_rounded,
                  text: MaterialLocalizations.of(context).formatTimeOfDay(
                    TimeOfDay(hour: reminder.hour, minute: reminder.minute),
                    alwaysUse24HourFormat:
                        MediaQuery.alwaysUse24HourFormatOf(context),
                  ),
                  color: color,
                ),
              if (habit.archived)
                _Pill(
                  key: const ValueKey('habit-archived'),
                  icon: Icons.inventory_2_rounded,
                  text: 'Archived',
                  color: theme.colorScheme.outline,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _Pill({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(text, style: theme.textTheme.labelLarge),
        ],
      ),
    );
  }
}
