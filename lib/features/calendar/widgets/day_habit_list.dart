import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/completion_log.dart';
import '../../../data/models/habit.dart';
import '../../../domain/providers.dart';

/// The habits due on the selected day, each with a check toggle.
///
/// Toggling works for today and past days; on future days ([readOnly]) the
/// toggle is disabled.
class DayHabitList extends ConsumerWidget {
  final DateTime date;
  final List<Habit> habits;
  final CompletionLog log;
  final bool readOnly;

  const DayHabitList({
    super.key,
    required this.date,
    required this.habits,
    required this.log,
    required this.readOnly,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (habits.isEmpty) {
      return Padding(
        key: const ValueKey('calendar-empty-day'),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            const Text('🏝️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            Text(
              'Nothing due this day — enjoy the break!',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final habit in habits)
          _HabitTile(
            habit: habit,
            done: log.isCompleted(habit.id, date),
            readOnly: readOnly,
            onToggle: () => ref
                .read(habitServiceProvider)
                .toggleCompletion(habit.id, date),
          ),
      ],
    );
  }
}

class _HabitTile extends StatelessWidget {
  final Habit habit;
  final bool done;
  final bool readOnly;
  final VoidCallback onToggle;

  const _HabitTile({
    required this.habit,
    required this.done,
    required this.readOnly,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = HabitPalette.fromValue(habit.colorValue);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      key: ValueKey('calendar-habit-${habit.id}'),
      color: done
          ? Color.alphaBlend(
              color.withValues(alpha: isDark ? 0.25 : 0.14),
              theme.colorScheme.surface,
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.22),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: Text(habit.emoji, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                key: ValueKey('calendar-habit-name-${habit.id}'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => context.push(AppRoutes.habitDetails(habit.id)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    habit.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      decoration: done ? TextDecoration.lineThrough : null,
                      decorationColor: color,
                      decorationThickness: 2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            if (readOnly)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Chip(
                  label: const Text('Soon'),
                  visualDensity: VisualDensity.compact,
                  avatar: const Text('🔒'),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  side: BorderSide.none,
                ),
              ),
            IconButton(
              key: ValueKey('calendar-toggle-${habit.id}'),
              tooltip: readOnly
                  ? 'Can’t check in the future'
                  : done
                      ? 'Undo check-in'
                      : 'Check in',
              iconSize: 34,
              onPressed: readOnly ? null : onToggle,
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
                  child: child,
                ),
                child: Icon(
                  done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  key: ValueKey(done),
                  color: readOnly
                      ? theme.disabledColor
                      : done
                          ? AppColors.success
                          : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
