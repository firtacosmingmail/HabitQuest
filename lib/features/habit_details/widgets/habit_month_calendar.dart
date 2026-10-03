import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../data/models/completion_log.dart';
import '../../../data/models/habit.dart';
import '../../../domain/recurrence.dart';

/// Key of a day cell, for tests: `day-yyyy-MM-dd`.
Key habitCalendarDayKey(DateTime date) => ValueKey('day-${dateKey(date)}');

/// A month heatmap of one habit's check-ins, Monday first, with month
/// navigation. Not-scheduled days are dimmed, completed days are filled with
/// the habit colour, today is outlined. Today and past days on/after the
/// start date are tappable ([onToggle]); future days are disabled.
class HabitMonthCalendar extends StatefulWidget {
  final Habit habit;
  final CompletionLog completions;
  final DateTime today;
  final ValueChanged<DateTime> onToggle;

  const HabitMonthCalendar({
    super.key,
    required this.habit,
    required this.completions,
    required this.today,
    required this.onToggle,
  });

  @override
  State<HabitMonthCalendar> createState() => _HabitMonthCalendarState();
}

class _HabitMonthCalendarState extends State<HabitMonthCalendar> {
  late DateTime _month = startOfMonth(widget.today);

  DateTime get _firstMonth {
    final dates = widget.completions.datesFor(widget.habit.id);
    var first = widget.habit.startDate;
    if (dates.isNotEmpty && dates.first.isBefore(first)) first = dates.first;
    final m = startOfMonth(first);
    final current = startOfMonth(widget.today);
    return m.isAfter(current) ? current : m;
  }

  DateTime get _lastMonth => startOfMonth(widget.today);

  void _go(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = HabitPalette.fromValue(widget.habit.colorValue);
    final canGoBack = _month.isAfter(_firstMonth);
    final canGoForward = _month.isBefore(_lastMonth);
    final monthEnd = DateTime(_month.year, _month.month, daysInMonth(_month));
    final monthCount =
        widget.completions.countInRange(widget.habit.id, _month, monthEnd);
    final title = MaterialLocalizations.of(context).formatMonthYear(_month);

    final leading = _month.weekday - DateTime.monday;
    final days = daysInMonth(_month);
    final cells = <DateTime?>[
      for (var i = 0; i < leading; i++) null,
      for (var day = 1; day <= days; day++)
        DateTime(_month.year, _month.month, day),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                key: const ValueKey('calendar-prev'),
                tooltip: 'Previous month',
                onPressed: canGoBack ? () => _go(-1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      title,
                      key: const ValueKey('calendar-title'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      monthCount == 1
                          ? '1 check-in'
                          : '$monthCount check-ins',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('calendar-next'),
                tooltip: 'Next month',
                onPressed: canGoForward ? () => _go(1) : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final label in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var row = 0; row < cells.length ~/ 7; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: cells[row * 7 + col] == null
                          ? const SizedBox.shrink()
                          : _DayCell(
                              key: habitCalendarDayKey(cells[row * 7 + col]!),
                              date: cells[row * 7 + col]!,
                              habit: widget.habit,
                              completions: widget.completions,
                              today: widget.today,
                              color: color,
                              onToggle: widget.onToggle,
                            ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime date;
  final Habit habit;
  final CompletionLog completions;
  final DateTime today;
  final Color color;
  final ValueChanged<DateTime> onToggle;

  const _DayCell({
    super.key,
    required this.date,
    required this.habit,
    required this.completions,
    required this.today,
    required this.color,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final done = completions.isCompleted(habit.id, date);
    final scheduled = isScheduledOn(habit, date);
    final isToday = date == today;
    final isFuture = date.isAfter(today);
    final enabled = !isFuture && !date.isBefore(habit.startDate);

    final Color background;
    final Color foreground;
    if (done) {
      background = color;
      foreground = HabitPalette.onColor(color);
    } else if (scheduled) {
      background = color.withValues(
        alpha: isFuture ? (isDark ? 0.10 : 0.07) : (isDark ? 0.22 : 0.14),
      );
      foreground = scheme.onSurface.withValues(alpha: isFuture ? 0.6 : 0.9);
    } else {
      background = Colors.transparent;
      foreground = scheme.onSurface.withValues(alpha: 0.3);
    }

    final label = StringBuffer(
      MaterialLocalizations.of(context).formatFullDate(date),
    )
      ..write(done ? ', done' : '')
      ..write(!scheduled ? ', not scheduled' : '')
      ..write(isToday ? ', today' : '');

    return Padding(
      padding: const EdgeInsets.all(3),
      child: Semantics(
        button: enabled,
        enabled: enabled,
        label: label.toString(),
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? () => onToggle(date) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: background,
                border: isToday
                    ? Border.all(
                        color: done ? scheme.onSurface : color,
                        width: 2.5,
                      )
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: done ? 0.35 : 0),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '${date.day}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: done || isToday
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
