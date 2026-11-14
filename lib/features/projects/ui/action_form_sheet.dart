import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/providers.dart';
import '../domain/overlap.dart';
import '../models/clock_time.dart';
import '../models/consistent_action.dart';
import '../models/target.dart';
import '../projects_providers.dart';
import 'widgets/project_widgets.dart';

/// Default times of a new consistent action.
const defaultActionStart = ClockTime(9, 0);
const defaultActionEnd = ClockTime(10, 0);

/// Opens the consistent action form for [target] (new when [action] is
/// null). Returns `true` when saved.
Future<bool> showActionForm(
  BuildContext context, {
  required Target target,
  ConsistentAction? action,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ActionFormSheet(target: target, action: action),
  );
  return saved ?? false;
}

enum _Mode { weekly, monthly }

/// CONSISTENT ACTION form: start / end time, days of the week OR days of
/// the month, optional start date. Clashes are shown live
/// ([ProjectService.clashesFor]); saving a clashing block is BLOCKED: the
/// service's [ActionOverlapException] message is shown and the form stays
/// open.
class ActionFormSheet extends ConsumerStatefulWidget {
  final Target target;
  final ConsistentAction? action;

  const ActionFormSheet({super.key, required this.target, this.action});

  @override
  ConsumerState<ActionFormSheet> createState() => _ActionFormSheetState();
}

class _ActionFormSheetState extends ConsumerState<ActionFormSheet> {
  late ClockTime _start;
  late ClockTime _end;
  late _Mode _mode;
  late Set<int> _weekdays;
  late Set<int> _monthDays;
  DateTime? _startDate;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.action;
    _start = a?.startTime ?? defaultActionStart;
    _end = a?.endTime ?? defaultActionEnd;
    _startDate = a?.startDate;
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

  ActionRecurrence? get _recurrence => switch (_mode) {
    _Mode.weekly => _weekdays.isEmpty ? null : WeeklyRecurrence(_weekdays),
    _Mode.monthly => _monthDays.isEmpty ? null : MonthlyRecurrence(_monthDays),
  };

  String? get _validation {
    if (!_start.isBefore(_end)) {
      return 'The end must be after the start (split blocks across midnight in two).';
    }
    if (_recurrence == null) return 'Pick at least one day.';
    return null;
  }

  /// The action as it would be saved (for the live clash check).
  ConsistentAction? _candidate() {
    final r = _recurrence;
    if (r == null || !_start.isBefore(_end)) return null;
    final existing = widget.action;
    return ConsistentAction(
      id: existing?.id ?? '__draft__',
      targetId: widget.target.id,
      startTime: _start,
      endTime: _end,
      recurrence: r,
      startDate: _startDate,
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

  Future<void> _save() async {
    if (_validation != null) return;
    final service = ref.read(projectServiceProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.action;
      if (existing == null) {
        await service.createAction(
          targetId: widget.target.id,
          startTime: _start,
          endTime: _end,
          recurrence: _recurrence!,
          startDate: _startDate,
        );
      } else {
        await service.updateAction(
          existing.copyWith(
            startTime: _start,
            endTime: _end,
            recurrence: _recurrence,
            startDate: () => _startDate,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ActionOverlapException catch (e) {
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
    final target = service.data.target(widget.target.id) ?? widget.target;
    final candidate = _candidate();
    final clashes = candidate == null
        ? const <ActionClash>[]
        : service.clashesFor(candidate, target: target);
    final validation = _validation;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        key: const ValueKey('action-form'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.action == null ? 'New time block' : 'Edit time block',
              style: theme.textTheme.headlineSmall,
            ),
            Text(
              'For “${target.title}”, up to its deadline (${longDate(target.deadline)}).',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _TimeButton(
                    key: const ValueKey('action-start'),
                    label: 'Start',
                    time: _start,
                    onTap: () => _pickTime(true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimeButton(
                    key: const ValueKey('action-end'),
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
                      key: ValueKey('action-weekday-$d'),
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
                      key: ValueKey('action-monthday-$d'),
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
                      key: const ValueKey('action-start-date'),
                      onPressed: _pickStartDate,
                      child: const Text('Pick'),
                    )
                  : IconButton(
                      key: const ValueKey('action-clear-start-date'),
                      tooltip: 'Clear start date',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _startDate = null),
                    ),
            ),
            if (validation != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  validation,
                  key: const ValueKey('action-validation'),
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
                key: const ValueKey('action-save-error'),
                message: _error!,
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('save-action'),
              onPressed: _saving || validation != null ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(widget.action == null ? 'Add time block' : 'Save'),
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
