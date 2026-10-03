import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../data/models/completion_log.dart';
import '../../data/models/habit.dart';
import '../../domain/providers.dart';
import '../../domain/recurrence.dart';
import 'calendar_month.dart';
import 'widgets/day_cell.dart';
import 'widgets/day_habit_list.dart';

/// Calendar tab (`/calendar`): a Monday-first month grid showing each day's
/// progress, with the selected day's due habits listed below.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month;
  late DateTime _selected;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    final today = ref.read(todayProvider);
    _month = startOfMonth(today);
    _selected = today;
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      final today = ref.read(todayProvider);
      // Keep the selection inside the visible month: today if it is there,
      // otherwise the 1st.
      _selected = isSameDay(startOfMonth(today), _month) ? today : _month;
    });
  }

  void _goToToday() {
    final today = ref.read(todayProvider);
    setState(() {
      _month = startOfMonth(today);
      _selected = today;
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final habits = ref.watch(habitsProvider);
    final log = ref.watch(completionsProvider);
    final onTodayView =
        isSameDay(_month, startOfMonth(today)) && isSameDay(_selected, today);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.tonalIcon(
              key: const ValueKey('calendar-today-button'),
              onPressed: onTodayView ? null : _goToToday,
              icon: const Icon(Icons.today_rounded),
              label: const Text('Today'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ),
        ],
      ),
      body: switch ((habits, log)) {
        (AsyncValue(error: final Object e), _) ||
        (_, AsyncValue(error: final Object e)) =>
          Center(child: Text('Oops, the calendar tripped: $e')),
        (AsyncValue(value: final List<Habit> h),
              AsyncValue(value: final CompletionLog l)) =>
          _body(context, today, h, l),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(
    BuildContext context,
    DateTime today,
    List<Habit> habits,
    CompletionLog log,
  ) {
    final theme = Theme.of(context);
    final cells = monthGridDays(_month);
    final perfectCount = perfectDaysInMonth(_month, today, habits, log);
    final selectedStatus = dayStatus(_selected, today, habits, log);
    final dueOnSelected = dueHabitsOn(habits, _selected, log);
    final selectedIsFuture = _selected.isAfter(today);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: (details) {
                    final v = details.primaryVelocity ?? 0;
                    if (v.abs() < 200) return;
                    _changeMonth(v < 0 ? 1 : -1);
                  },
                  child: Column(
                    children: [
                      _MonthHeader(
                        month: _month,
                        onPrevious: () => _changeMonth(-1),
                        onNext: () => _changeMonth(1),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          for (final w in _weekdays)
                            Expanded(
                              child: Center(
                                child: Text(
                                  w,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Column(
                          key: ValueKey(dateKey(_month)),
                          children: [
                            for (var r = 0; r < cells.length; r += 7)
                              Row(
                                children: [
                                  for (final day in cells.sublist(r, r + 7))
                                    Expanded(
                                      child: AspectRatio(
                                        aspectRatio: 1,
                                        child: day == null
                                            ? const SizedBox.shrink()
                                            : DayCell(
                                                status: dayStatus(
                                                    day, today, habits, log),
                                                isToday: isSameDay(day, today),
                                                isSelected:
                                                    isSameDay(day, _selected),
                                                onTap: () => setState(
                                                    () => _selected = day),
                                              ),
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _MonthSummary(count: perfectCount),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedTitle(today),
                      key: const ValueKey('calendar-selected-title'),
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  if (selectedStatus.kind == DayKind.tracked)
                    Text(
                      selectedStatus.isPerfect
                          ? '⭐ Perfect!'
                          : '${selectedStatus.done}/${selectedStatus.due} done',
                      key: const ValueKey('calendar-selected-progress'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: selectedStatus.isPerfect
                            ? const Color(0xFFB8860B)
                            : AppColors.success,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
            if (selectedIsFuture && dueOnSelected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Text(
                  'A peek at what’s coming — check-ins open on the day.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            DayHabitList(
              date: _selected,
              habits: dueOnSelected,
              log: log,
              readOnly: selectedIsFuture,
            ),
          ],
        ),
      ),
    );
  }

  String _selectedTitle(DateTime today) {
    if (isSameDay(_selected, today)) return 'Today';
    final diff = daysBetween(today, _selected);
    if (diff == -1) return 'Yesterday';
    if (diff == 1) return 'Tomorrow';
    return DateFormat('EEEE, MMM d').format(_selected);
  }
}

class _MonthHeader extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton.filledTonal(
          key: const ValueKey('calendar-prev-month'),
          tooltip: 'Previous month',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            DateFormat('MMMM yyyy').format(month),
            key: const ValueKey('calendar-month-title'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
        ),
        IconButton.filledTonal(
          key: const ValueKey('calendar-next-month'),
          tooltip: 'Next month',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _MonthSummary extends StatelessWidget {
  final int count;

  const _MonthSummary({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = switch (count) {
      0 => 'No Perfect Days yet this month — today could be the one!',
      1 => '⭐ 1 Perfect Day this month',
      _ => '⭐ $count Perfect Days this month',
    };
    return Container(
      key: const ValueKey('calendar-month-summary'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.perfectDay.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.18 : 0.25,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
