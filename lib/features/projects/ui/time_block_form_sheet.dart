import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/providers.dart';
import '../domain/overlap.dart';
import '../models/clock_time.dart';
import '../models/project.dart';
import '../models/time_block.dart';
import '../projects_providers.dart';
import 'widgets/project_widgets.dart';

/// Default times of a new time block.
const defaultBlockStart = ClockTime(9, 0);
const defaultBlockEnd = ClockTime(10, 0);

/// Opens the time block form for [project] (new when [block] is null).
/// Returns `true` when saved.
Future<bool> showTimeBlockForm(
  BuildContext context, {
  required Project project,
  TimeBlock? block,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => TimeBlockFormSheet(project: project, block: block),
  );
  return saved ?? false;
}

enum _Mode { weekly, monthly }

/// TIME BLOCK form (project level): optional label, start / end time, days
/// of the week OR days of the month, optional start and end dates
/// (open-ended without an end date). Clashes with any project's blocks are
/// shown live ([ProjectService.clashesFor]); saving a clashing block is
/// BLOCKED: the service's [TimeBlockOverlapException] message is shown and
/// the form stays open.
class TimeBlockFormSheet extends ConsumerStatefulWidget {
  final Project project;
  final TimeBlock? block;

  const TimeBlockFormSheet({super.key, required this.project, this.block});

  @override
  ConsumerState<TimeBlockFormSheet> createState() =>
      _TimeBlockFormSheetState();
}

class _TimeBlockFormSheetState extends ConsumerState<TimeBlockFormSheet> {
  late final _label = TextEditingController(text: widget.block?.label ?? '');
  late ClockTime _start;
  late ClockTime _end;
  late _Mode _mode;
  late Set<int> _weekdays;
  late Set<int> _monthDays;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.block;
    _start = a?.startTime ?? defaultBlockStart;
    _end = a?.endTime ?? defaultBlockEnd;
    _startDate = a?.startDate;
    _endDate = a?.endDate;
    switch (a?.recurrence) {
      case MonthlyRecurrence(:final monthDays):
        _mode = _Mode.monthly;
        _monthDays = {...monthDays};
        _weekdays = {1, 2, 3, 4, 5};
      case WeeklyRecurrence(:final weekdays):
        _mode = _Mode.weekly;
        _weekdays = {...weekdays};
        _monthDays = {1};
      case null:
        _mode = _Mode.weekly;
        _weekdays = {1, 2, 3, 4, 5};
        _monthDays = {1};
    }
  }

  BlockRecurrence? get _recurrence => switch (_mode) {
    _Mode.weekly => _weekdays.isEmpty ? null : WeeklyRecurrence(_weekdays),
    _Mode.monthly => _monthDays.isEmpty ? null : MonthlyRecurrence(_monthDays),
  };

  String? get _validation {
    if (!_start.isBefore(_end)) {
      return 'The end must be after the start (split blocks across midnight in two).';
    }
    if (_recurrence == null) return 'Pick at least one day.';
    final s = _startDate, e = _endDate;
    if (s != null && e != null && e.isBefore(s)) {
      return 'The end date must not be before the start date.';
    }
    return null;
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  /// The block as it would be saved (for the live clash check).
  TimeBlock? _candidate() {
    final r = _recurrence;
    if (r == null || _validation != null) return null;
    final existing = widget.block;
    return TimeBlock(
      id: existing?.id ?? '__draft__',
      projectId: widget.project.id,
      label: _label.text,
      startTime: _start,
      endTime: _end,
      recurrence: r,
      startDate: _startDate,
      endDate: _endDate,
      createdAt: existing?.createdAt ?? ref.read(clockProvider)(),
    );
  }

  Future<void> _pickTime(bool start) async {
    final current = start ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) return;
    setState(() {
      final t = ClockTime(picked.hour, picked.minute);
      if (start) {
        _start = t;
      } else {
        _end = t;
      }
      _error = null;
    });
  }

  Future<void> _pickStartDate() async {
    final today = ref.read(todayProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? today,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        _error = null;
      });
    }
  }

  Future<void> _pickEndDate() async {
    final today = ref.read(todayProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? today,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    if (_validation != null) return;
    final service = ref.read(projectServiceProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.block;
      if (existing == null) {
        await service.createTimeBlock(
          projectId: widget.project.id,
          label: _label.text,
          startTime: _start,
          endTime: _end,
          recurrence: _recurrence!,
          startDate: _startDate,
          endDate: _endDate,
        );
      } else {
        await service.updateTimeBlock(
          existing.copyWith(
            label: () => _label.text,
            startTime: _start,
            endTime: _end,
            recurrence: _recurrence,
            startDate: () => _startDate,
            endDate: () => _endDate,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on TimeBlockOverlapException catch (e) {
      // BLOCKED: keep the form open with the message.
      if (mounted) setState(() => _error = e.message);
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = '${e.message}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Rebuild on data changes so the live clash check stays current.
    ref.watch(projectsDataProvider);
    final service = ref.read(projectServiceProvider);
    final candidate = _candidate();
    final clashes = candidate == null
        ? const <TimeBlockClash>[]
        : service.clashesFor(candidate);
    final validation = _validation;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        key: const ValueKey('time-block-form'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.block == null ? 'New time block' : 'Edit time block',
              style: theme.textTheme.headlineSmall,
            ),
            Text(
              'For “${widget.project.name}”.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('block-label'),
              controller: _label,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() => _error = null),
              decoration: const InputDecoration(
                labelText: 'Label (optional)',
                hintText: 'e.g. Editing',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _TimeButton(
                    key: const ValueKey('block-start'),
                    label: 'Start',
                    time: _start,
                    onTap: () => _pickTime(true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimeButton(
                    key: const ValueKey('block-end'),
                    label: 'End',
                    time: _end,
                    onTap: () => _pickTime(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SegmentedButton<_Mode>(
              segments: const [
                ButtonSegment(
                  value: _Mode.weekly,
                  label: Text('Days of the week', key: ValueKey('mode-weekly')),
                ),
                ButtonSegment(
                  value: _Mode.monthly,
                  label: Text(
                    'Days of the month',
                    key: ValueKey('mode-monthly'),
                  ),
                ),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                _mode = s.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 12),
            if (_mode == _Mode.weekly)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var d = 1; d <= 7; d++)
                    FilterChip(
                      key: ValueKey('block-weekday-$d'),
                      label: Text(
                        const [
                          'Mon',
                          'Tue',
                          'Wed',
                          'Thu',
                          'Fri',
                          'Sat',
                          'Sun',
                        ][d - 1],
                      ),
                      selected: _weekdays.contains(d),
                      onSelected: (on) => setState(() {
                        on ? _weekdays.add(d) : _weekdays.remove(d);
                        _error = null;
                      }),
                    ),
                ],
              )
            else ...[
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (var d = 1; d <= 31; d++)
                    _DayBubble(
                      key: ValueKey('block-monthday-$d'),
                      day: d,
                      selected: _monthDays.contains(d),
                      onTap: () => setState(() {
                        _monthDays.contains(d)
                            ? _monthDays.remove(d)
                            : _monthDays.add(d);
                        _error = null;
                      }),
                    ),
                ],
              ),
              if (_monthDays.any((d) => d > 28))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Months without that day have no session for it.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: const Text('Start date'),
              subtitle: Text(
                _startDate == null
                    ? 'From the day it is created'
                    : 'From ${longDate(_startDate!)}',
              ),
              onTap: _pickStartDate,
              trailing: _startDate == null
                  ? TextButton(
                      key: const ValueKey('block-start-date'),
                      onPressed: _pickStartDate,
                      child: const Text('Pick'),
                    )
                  : IconButton(
                      key: const ValueKey('block-clear-start-date'),
                      tooltip: 'Clear start date',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _startDate = null),
                    ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available_rounded),
              title: const Text('End date'),
              subtitle: Text(
                _endDate == null
                    ? 'Ongoing (no end date)'
                    : 'Until ${longDate(_endDate!)}',
              ),
              onTap: _pickEndDate,
              trailing: _endDate == null
                  ? TextButton(
                      key: const ValueKey('block-end-date'),
                      onPressed: _pickEndDate,
                      child: const Text('Pick'),
                    )
                  : IconButton(
                      key: const ValueKey('block-clear-end-date'),
                      tooltip: 'Clear end date',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _endDate = null),
                    ),
            ),
            if (validation != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  validation,
                  key: const ValueKey('block-validation'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            if (clashes.isNotEmpty && _error == null) ...[
              ClashList(clashes: clashes),
              const SizedBox(height: 8),
            ],
            if (_error != null) ...[
              OverlapMessageCard(
                key: const ValueKey('time-block-save-error'),
                message: _error!,
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('save-time-block'),
              onPressed: _saving || validation != null ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(widget.block == null ? 'Add time block' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final ClockTime time;
  final VoidCallback onTap;

  const _TimeButton({
    super.key,
    required this.label,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Column(
            children: [
              Text(label, style: theme.textTheme.labelLarge),
              Text('$time', style: theme.textTheme.headlineSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayBubble extends StatelessWidget {
  final int day;
  final bool selected;
  final VoidCallback onTap;

  const _DayBubble({
    super.key,
    required this.day,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Day $day',
      excludeSemantics: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected
                ? scheme.primary
                : scheme.primary.withValues(alpha: 0.08),
          ),
          child: Text(
            '$day',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? scheme.onPrimary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
