import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/message_view.dart';
import '../../../domain/providers.dart';
import '../domain/overlap.dart';
import '../models/consistent_action.dart';
import '../models/plan_task.dart';
import '../models/target.dart';
import '../projects_providers.dart';
import 'action_form_sheet.dart';
import 'widgets/project_widgets.dart';

/// Target create (`/projects/:id/targets/new`, [targetId] == null) and edit
/// (`/projects/:id/targets/:tid`): title, deadline and status (manual), the
/// PLAN (tasks with an optional delivery date, checked off by the user) and
/// the CONSISTENT ACTIONS (time blocks).
///
/// After creating, the screen is replaced by the editor of the new target
/// so the plan and time blocks can be added.
class TargetEditorScreen extends ConsumerStatefulWidget {
  final String projectId;
  final String? targetId;

  const TargetEditorScreen({super.key, required this.projectId, this.targetId});

  bool get isNew => targetId == null;

  @override
  ConsumerState<TargetEditorScreen> createState() => _TargetEditorScreenState();
}

class _TargetEditorScreenState extends ConsumerState<TargetEditorScreen> {
  final _title = TextEditingController();
  late DateTime _deadline;
  TargetStatus _status = TargetStatus.notStarted;
  Target? _original;
  String? _error;
  String? _titleError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _deadline = addDays(ref.read(todayProvider), 30);
    final id = widget.targetId;
    if (id != null) {
      final t = ref.read(projectServiceProvider).data.target(id);
      if (t != null) _load(t);
    }
  }

  void _load(Target t) {
    _original = t;
    _title.text = t.title;
    _deadline = t.deadline;
    _status = t.status;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _dirty {
    final o = _original;
    if (o == null) return true;
    return _title.text.trim() != o.title ||
        _deadline != o.deadline ||
        _status != o.status;
  }

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Deadline',
    );
    if (picked != null) {
      setState(() {
        _deadline = dateOnly(picked);
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Give your target a title');
      return;
    }
    final service = ref.read(projectServiceProvider);
    setState(() {
      _saving = true;
      _error = null;
      _titleError = null;
    });
    try {
      final o = _original;
      if (o == null) {
        final t = await service.createTarget(
          projectId: widget.projectId,
          title: title,
          deadline: _deadline,
          status: _status,
        );
        if (mounted) {
          context.pushReplacement(
            AppRoutes.targetEditor(widget.projectId, t.id),
          );
        }
        return;
      }
      final saved = await service.updateTarget(
        o.copyWith(title: title, deadline: _deadline, status: _status),
      );
      if (mounted) {
        setState(() => _load(saved));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Target saved ✨')));
      }
    } on ActionOverlapException catch (e) {
      // Refused (a later deadline or reopening would clash): nothing saved.
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final o = _original;
    if (o == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Delete “${o.title}”?',
      message: 'Its plan and time blocks are deleted too.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    await ref.read(projectServiceProvider).deleteTarget(o.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = ref.watch(projectByIdProvider(widget.projectId)).value;
    final live = widget.targetId == null
        ? null
        : ref.watch(targetByIdProvider(widget.targetId!));

    if (widget.targetId != null &&
        live != null &&
        live.hasValue &&
        live.value == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const MessageView(
          key: ValueKey('target-not-found'),
          emoji: '🎯',
          title: 'Target not found',
          message: 'It may have been deleted.',
        ),
      );
    }
    // Opened before the data arrived: load once it is there.
    if (_original == null && live?.value != null) _load(live!.value!);

    final color = projectColor(widget.projectId);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New target' : 'Target'),
        actions: [
          if (!widget.isNew)
            IconButton(
              key: const ValueKey('delete-target'),
              tooltip: 'Delete target',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        key: const ValueKey('target-editor-list'),
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          if (project != null) NoteText('In ${project.name}'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              key: const ValueKey('target-title'),
              controller: _title,
              onChanged: (_) => setState(() => _titleError = null),
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. 5 videos',
                errorText: _titleError,
              ),
            ),
          ),
          ListTile(
            key: const ValueKey('target-deadline'),
            leading: Icon(Icons.flag_rounded, color: color),
            title: const Text('Deadline'),
            subtitle: Text(longDate(_deadline)),
            trailing: const Icon(Icons.edit_calendar_rounded),
            onTap: _pickDeadline,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('Status', style: theme.textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: SegmentedButton<TargetStatus>(
              key: const ValueKey('target-status'),
              showSelectedIcon: false,
              segments: [
                for (final s in TargetStatus.values)
                  ButtonSegment(
                    value: s,
                    icon: Icon(statusIcon(s)),
                    label: Text(
                      statusLabel(s),
                      key: ValueKey('status-${s.name}'),
                    ),
                  ),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() {
                _status = s.first;
                _error = null;
              }),
            ),
          ),
          const NoteText(
            'You set the status yourself; the app never changes it.',
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: OverlapMessageCard(
                key: const ValueKey('target-save-error'),
                title: 'Change refused: it would clash',
                message: _error!,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: FilledButton.icon(
              key: const ValueKey('save-target'),
              onPressed: _saving || !_dirty ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(widget.isNew ? 'Create target' : 'Save changes'),
            ),
          ),
          if (_original != null) ...[
            _PlanSection(target: _original!, color: color),
            _ActionsSection(target: _original!, color: color),
          ] else
            const NoteText(
              'Create the target first, then add its plan and time blocks.',
            ),
        ],
      ),
    );
  }
}

// Plan -----------------------------------------------------------------------

class _PlanSection extends ConsumerWidget {
  final Target target;
  final Color color;

  const _PlanSection({required this.target, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks =
        ref.watch(planTasksOfTargetProvider(target.id)).value ??
        const <PlanTask>[];
    final progress = ref.watch(planProgressProvider(target.id));
    final service = ref.read(projectServiceProvider);

    Future<void> add() async {
      final r = await showPlanTaskDialog(context);
      if (r == null) return;
      await service.addPlanTask(
        targetId: target.id,
        title: r.title,
        deliveryDate: r.deliveryDate,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Plan',
          trailing: TextButton.icon(
            key: const ValueKey('add-plan-task'),
            onPressed: add,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add task'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: PlanProgressBar(
            done: progress.done,
            total: progress.total,
            color: color,
          ),
        ),
        if (tasks.isEmpty)
          const NoteText(
            'Break the target into tasks: scripts, recordings, edits…',
          ),
        for (final t in tasks) _PlanTaskTile(task: t, color: color),
      ],
    );
  }
}

class _PlanTaskTile extends ConsumerWidget {
  final PlanTask task;
  final Color color;

  const _PlanTaskTile({required this.task, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(projectServiceProvider);
    final theme = Theme.of(context);

    Future<void> edit() async {
      final r = await showPlanTaskDialog(context, task: task);
      if (r == null) return;
      await service.updatePlanTask(
        task.copyWith(title: r.title, deliveryDate: () => r.deliveryDate),
      );
    }

    return Card(
      key: ValueKey('plan-task-${task.id}'),
      child: ListTile(
        leading: Checkbox(
          key: ValueKey('plan-task-done-${task.id}'),
          value: task.done,
          activeColor: color,
          shape: const CircleBorder(),
          onChanged: (v) => service.setPlanTaskDone(task.id, v ?? false),
        ),
        title: Text(
          task.title,
          style: task.done
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : null,
        ),
        subtitle: task.deliveryDate == null
            ? null
            : Text('Deliver by ${longDate(task.deliveryDate!)}'),
        onTap: edit,
        trailing: IconButton(
          key: ValueKey('plan-task-delete-${task.id}'),
          tooltip: 'Remove task',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => service.deletePlanTask(task.id),
        ),
      ),
    );
  }
}

/// Result of [showPlanTaskDialog].
typedef PlanTaskInput = ({String title, DateTime? deliveryDate});

/// Add / edit a plan task: title and optional delivery date.
Future<PlanTaskInput?> showPlanTaskDialog(
  BuildContext context, {
  PlanTask? task,
}) => showDialog<PlanTaskInput>(
  context: context,
  builder: (_) => _PlanTaskDialog(task: task),
);

class _PlanTaskDialog extends StatefulWidget {
  final PlanTask? task;

  const _PlanTaskDialog({this.task});

  @override
  State<_PlanTaskDialog> createState() => _PlanTaskDialogState();
}

class _PlanTaskDialogState extends State<_PlanTaskDialog> {
  late final _title = TextEditingController(text: widget.task?.title ?? '');
  late DateTime? _date = widget.task?.deliveryDate;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _title.text.trim();
    if (t.isEmpty) {
      setState(() => _error = 'Give the task a title');
      return;
    }
    Navigator.of(context).pop((title: t, deliveryDate: _date));
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? dateOnly(now),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Delivery date',
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.task == null ? 'New task' : 'Edit task'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('plan-task-title'),
            controller: _title,
            autofocus: true,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'Task', errorText: _error),
            onSubmitted: (_) => _submit(),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.local_shipping_rounded),
            title: const Text('Delivery date'),
            subtitle: Text(_date == null ? 'Optional' : longDate(_date!)),
            onTap: _pick,
            trailing: _date == null
                ? TextButton(
                    key: const ValueKey('plan-task-pick-date'),
                    onPressed: _pick,
                    child: const Text('Pick'),
                  )
                : IconButton(
                    key: const ValueKey('plan-task-clear-date'),
                    tooltip: 'Clear delivery date',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _date = null),
                  ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('plan-task-save'),
          onPressed: _submit,
          child: Text(widget.task == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}

// Consistent actions ---------------------------------------------------------

class _ActionsSection extends ConsumerWidget {
  final Target target;
  final Color color;

  const _ActionsSection({required this.target, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions =
        ref.watch(actionsOfTargetProvider(target.id)).value ??
        const <ConsistentAction>[];
    // The editor's copy may be stale after a save: use the stored target.
    final current = ref.watch(targetByIdProvider(target.id)).value ?? target;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Time blocks',
          trailing: TextButton.icon(
            key: const ValueKey('add-action'),
            onPressed: () => showActionForm(context, target: current),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add'),
          ),
        ),
        const NoteText(
          'Consistent actions: regular sessions up to the deadline. Time blocks never overlap.',
        ),
        for (final a in actions)
          ConsistentActionTile(
            action: a,
            color: color,
            onTap: () => showActionForm(context, target: current, action: a),
          ),
      ],
    );
  }
}

/// A consistent action: recurrence, times and optional start date.
class ConsistentActionTile extends ConsumerWidget {
  final ConsistentAction action;
  final Color color;
  final VoidCallback? onTap;

  const ConsistentActionTile({
    super.key,
    required this.action,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = action;
    return Card(
      key: ValueKey('action-tile-${a.id}'),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.18),
          child: Icon(Icons.schedule_rounded, color: color),
        ),
        title: Text(
          '${describeRecurrence(a.recurrence)} · ${a.startTime}–${a.endTime}',
        ),
        subtitle: a.startDate == null
            ? null
            : Text('From ${longDate(a.startDate!)}'),
        onTap: onTap,
        trailing: IconButton(
          key: ValueKey('action-delete-${a.id}'),
          tooltip: 'Delete time block',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            final ok = await confirmDialog(
              context,
              title: 'Delete this time block?',
              message: 'Its sessions and attended marks disappear too.',
              confirmLabel: 'Delete',
            );
            if (ok) await ref.read(projectServiceProvider).deleteAction(a.id);
          },
        ),
      ),
    );
  }
}
