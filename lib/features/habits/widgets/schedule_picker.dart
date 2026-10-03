import 'package:flutter/material.dart';

import '../../../core/constants/habit_defaults.dart';
import '../../../data/models/habit_schedule.dart';

/// The kinds of schedule offered by [SchedulePicker].
enum ScheduleKind { daily, weekdays, everyNDays, timesPerWeek }

/// Segmented schedule picker: Daily / Weekdays (chips) / Every N days
/// (stepper 2–30) / X times per week (stepper 1–6).
///
/// Reports `null` through [onChanged] while the selection is invalid (no
/// weekday picked). Keys: `weekday-<1..7>`, `everyN-dec/inc`, `times-dec/inc`.
class SchedulePicker extends StatefulWidget {
  final HabitSchedule initial;
  final ValueChanged<HabitSchedule?> onChanged;
  final Color accent;

  static const minEveryN = 2;
  static const maxEveryN = 30;
  static const minTimes = 1;
  static const maxTimes = 6;

  const SchedulePicker({
    super.key,
    required this.initial,
    required this.onChanged,
    required this.accent,
  });

  @override
  State<SchedulePicker> createState() => _SchedulePickerState();
}

class _SchedulePickerState extends State<SchedulePicker> {
  late ScheduleKind _kind;
  Set<int> _days = {1, 2, 3, 4, 5};
  int _everyN = 2;
  int _times = 3;

  @override
  void initState() {
    super.initState();
    switch (widget.initial) {
      case DailySchedule():
        _kind = ScheduleKind.daily;
      case WeekdaysSchedule(:final days):
        _kind = ScheduleKind.weekdays;
        _days = {...days};
      case EveryNDaysSchedule(:final n):
        _kind = ScheduleKind.everyNDays;
        _everyN = n.clamp(SchedulePicker.minEveryN, SchedulePicker.maxEveryN);
      case TimesPerWeekSchedule(:final times):
        _kind = ScheduleKind.timesPerWeek;
        _times = times.clamp(SchedulePicker.minTimes, SchedulePicker.maxTimes);
    }
  }

  HabitSchedule? get _schedule => switch (_kind) {
    ScheduleKind.daily => const DailySchedule(),
    ScheduleKind.weekdays => _days.isEmpty ? null : WeekdaysSchedule(_days),
    ScheduleKind.everyNDays => EveryNDaysSchedule(_everyN),
    ScheduleKind.timesPerWeek => TimesPerWeekSchedule(_times),
  };

  void _update(VoidCallback change) {
    setState(change);
    widget.onChanged(_schedule);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<ScheduleKind>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: ScheduleKind.daily, label: Text('Daily')),
            ButtonSegment(
              value: ScheduleKind.weekdays,
              label: Text('Weekdays'),
            ),
            ButtonSegment(
              value: ScheduleKind.everyNDays,
              label: Text('Every N'),
            ),
            ButtonSegment(
              value: ScheduleKind.timesPerWeek,
              label: Text('Per week'),
            ),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => _update(() => _kind = s.first),
        ),
        const SizedBox(height: 12),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: switch (_kind) {
            ScheduleKind.daily => _hint(theme, 'Every single day. Bold! 💪'),
            ScheduleKind.weekdays => _weekdayChips(theme),
            ScheduleKind.everyNDays => NumberStepper(
              keyPrefix: 'everyN',
              value: _everyN,
              min: SchedulePicker.minEveryN,
              max: SchedulePicker.maxEveryN,
              label: 'Every $_everyN days',
              onChanged: (v) => _update(() => _everyN = v),
            ),
            ScheduleKind.timesPerWeek => NumberStepper(
              keyPrefix: 'times',
              value: _times,
              min: SchedulePicker.minTimes,
              max: SchedulePicker.maxTimes,
              label: '$_times× per week',
              onChanged: (v) => _update(() => _times = v),
            ),
          },
        ),
      ],
    );
  }

  Widget _hint(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _weekdayChips(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in HabitDefaults.weekdayShort.entries)
              FilterChip(
                key: ValueKey('weekday-${e.key}'),
                label: Text(e.value),
                showCheckmark: false,
                selected: _days.contains(e.key),
                selectedColor: widget.accent.withValues(alpha: 0.3),
                onSelected: (on) => _update(() {
                  _days = {..._days};
                  on ? _days.add(e.key) : _days.remove(e.key);
                }),
              ),
          ],
        ),
        if (_days.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              'Pick at least one day',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

/// A − value + stepper. Buttons have keys `<keyPrefix>-dec` / `-inc`.
class NumberStepper extends StatelessWidget {
  final String keyPrefix;
  final int value;
  final int min;
  final int max;
  final String label;
  final ValueChanged<int> onChanged;

  const NumberStepper({
    super.key,
    required this.keyPrefix,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton.filledTonal(
          key: ValueKey('$keyPrefix-dec'),
          tooltip: 'Less',
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton.filledTonal(
          key: ValueKey('$keyPrefix-inc'),
          tooltip: 'More',
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}
