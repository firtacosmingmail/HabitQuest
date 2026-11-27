import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/message_view.dart';
import '../../../domain/providers.dart';
import '../models/consistent_action.dart';
import '../models/plan_task.dart';
import '../models/goal.dart';
import '../projects_providers.dart';
import 'widgets/project_widgets.dart';

/// Goal create (`/projects/:id/goals/new`, [goalId] == null) and edit
/// (`/projects/:id/goals/:gid`): title, deadline and status (manual), the
/// PLAN (tasks with an optional delivery date, checked off by the user) and
/// the CONSISTENT ACTIONS (text items). Time blocks live on the project.
///
/// After creating, the screen is replaced by the editor of the new goal so
/// the plan and actions can be added.
class GoalEditorScreen extends ConsumerStatefulWidget {
  final String projectId;
  final String? goalId;

  const GoalEditorScreen({super.key, required this.projectId, this.goalId});

  bool get isNew => goalId == null;

  @override
  ConsumerState<GoalEditorScreen> createState() => _GoalEditorScreenState();
}

class _GoalEditorScreenState extends ConsumerState<GoalEditorScreen> {
  final _title = TextEditingController();
  late DateTime _deadline;
  GoalStatus _status = GoalStatus.notStarted;
  Goal? _original;
  String? _error;
  String? _titleError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _deadline = addDays(ref.read(todayProvider), 30);
    final id = widget.goalId;
    if (id != null) {
      final t = ref.read(projectServiceProvider).data.goal(id);
      if (t != null) _load(t);
    }
  }

  void _load(Goal t) {
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
      setState(() => _titleError = 'Give your goal a title');
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
        final t = await service.createGoal(
          projectId: widget.projectId,
          title: title,
          deadline: _deadline,
          status: _status,
        );
        if (mounted) {
          context.pushReplacement(
            AppRoutes.goalEditor(widget.projectId, t.id),
          );
        }
        return;
      }
      final saved = await service.updateGoal(
        o.copyWith(title: title, deadline: _deadline, status: _status),
      );
      if (mounted) {
        setState(() => _load(saved));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Goal saved ✨')));
      }
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = '${e.message}');
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
      message: 'Its plan and consistent actions are deleted too.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    await ref.read(projectServiceProvider).deleteGoal(o.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = ref.watch(projectByIdProvider(widget.projectId)).value;
    final live = widget.goalId == null
        ? null
        : ref.watch(goalByIdProvider(widget.goalId!));

    if (widget.goalId != null &&
        live != null &&
        live.hasValue &&
        live.value == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const MessageView(
          key: ValueKey('goal-not-found'),
          emoji: '🎯',
          title: 'Goal not found',
          message: 'It may have been deleted.',
        ),
      );
    }
    // Opened before the data arrived: load once it is there.
    if (_original == null && live?.value != null) _load(live!.value!);

    final color = projectColor(widget.projectId);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New goal' : 'Goal'),
        actions: [
          if (!widget.isNew)
            IconButton(
              key: const ValueKey('delete-goal'),
              tooltip: 'Delete goal',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        key: const ValueKey('goal-editor-list'),
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          if (project != null) NoteText('In ${project.name}'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              key: const ValueKey('goal-title'),
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
            key: const ValueKey('goal-deadline'),
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
            child: SegmentedButton<GoalStatus>(
              key: const ValueKey('goal-status'),
              showSelectedIcon: false,
              segments: [
                for (final s in GoalStatus.values)
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
                key: const ValueKey('goal-save-error'),
                title: 'Could not save',
                message: _error!,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: FilledButton.icon(
              key: const ValueKey('save-goal'),
              onPressed: _saving || !_dirty ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(widget.isNew ? 'Create goal' : 'Save changes'),
            ),
          ),
          if (_original != null) ...[
            _PlanSection(goal: _original!, color: color),
            _ConsistentActionsSection(goal: _original!, color: color),
          ] else
            const NoteText(
              'Create the goal first, then add its plan and actions.',
            ),
        ],
      ),
    );
  }
}

// Plan -----------------------------------------------------------------------

class _PlanSection extends ConsumerWidget {
  final Goal goal;
  final Color color;

  const _PlanSection({required this.goal, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks =
        ref.watch(planTasksOfGoalProvider(goal.id)).value ??
        const <PlanTask>[];
    final progress = watchPlanProgress(ref, goal.id);
    final service = ref.read(projectServiceProvider);

    Future<void> add() async {
      final r = await showPlanTaskDialog(context);
      if (r == null) return;
      await service.addPlanTask(
        goalId: goal.id,
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
            'Break the goal into tasks: scripts, recordings, edits…',
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

// Consistent actions (text items) --------------------------------------------

/// Longest consistent action text (the server accepts up to 500).
const consistentActionMaxLength = 200;

/// The goal's consistent actions: a simple list of text items. Add with the
/// field at the bottom, tap a text to edit it in place, drag the handle to
/// reorder, ✕ to delete. No times, no tick-off, no XP.
class _ConsistentActionsSection extends ConsumerStatefulWidget {
  final Goal goal;
  final Color color;

  const _ConsistentActionsSection({required this.goal, required this.color});

  @override
  ConsumerState<_ConsistentActionsSection> createState() =>
      _ConsistentActionsSectionState();
}

class _ConsistentActionsSectionState
    extends ConsumerState<_ConsistentActionsSection> {
  final _newText = TextEditingController();
  final _newFocus = FocusNode();

  /// The order just dropped by the user, shown until the saved order
  /// arrives (avoids a flicker back to the old order).
  List<String>? _pendingOrder;

  @override
  void dispose() {
    _newText.dispose();
    _newFocus.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _newText.text.trim();
    if (text.isEmpty) return;
    _newText.clear();
    await ref
        .read(projectServiceProvider)
        .addConsistentAction(goalId: widget.goal.id, text: text);
    if (mounted) _newFocus.requestFocus();
  }

  List<ConsistentAction> _ordered(List<ConsistentAction> saved) {
    final pending = _pendingOrder;
    if (pending == null) return saved;
    final byId = {for (final a in saved) a.id: a};
    final sameSet =
        pending.length == saved.length && pending.every(byId.containsKey);
    if (!sameSet) return saved;
    return [for (final id in pending) byId[id]!];
  }

  Future<void> _reorder(List<ConsistentAction> items, int from, int to) async {
    // `to` is already adjusted for the removed item (onReorderItem).
    final ids = items.map((a) => a.id).toList();
    if (from == to) return;
    ids.insert(to, ids.removeAt(from));
    setState(() => _pendingOrder = ids);
    try {
      await ref
          .read(projectServiceProvider)
          .reorderConsistentActions(widget.goal.id, ids);
    } on ArgumentError {
      // The list changed underneath (e.g. a sync): show the saved order.
    } finally {
      if (mounted) setState(() => _pendingOrder = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved =
        ref.watch(consistentActionsOfGoalProvider(widget.goal.id)).value ??
        const <ConsistentAction>[];
    final actions = _ordered(saved);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Consistent actions'),
        NoteText(
          actions.isEmpty
              ? 'What will you keep doing to get there? e.g. “Post one short '
                    'a day”.'
              : 'Tap to edit, drag ≡ to reorder.',
        ),
        ReorderableListView(
          key: const ValueKey('consistent-actions-list'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          padding: EdgeInsets.zero,
          onReorderItem: (from, to) => _reorder(actions, from, to),
          proxyDecorator: (child, _, animation) => AnimatedBuilder(
            animation: animation,
            builder: (context, child) => Material(
              color: Colors.transparent,
              elevation: 6 * animation.value,
              shadowColor: widget.color.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
              child: child,
            ),
            child: child,
          ),
          children: [
            for (var i = 0; i < actions.length; i++)
              _ConsistentActionTile(
                key: ValueKey('consistent-action-${actions[i].id}'),
                action: actions[i],
                index: i,
                color: widget.color,
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('consistent-action-new'),
                  controller: _newText,
                  focusNode: _newFocus,
                  maxLength: consistentActionMaxLength,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _add(),
                  decoration: const InputDecoration(
                    hintText: 'Add a consistent action',
                    prefixIcon: Icon(Icons.repeat_rounded),
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                key: const ValueKey('add-consistent-action'),
                tooltip: 'Add',
                onPressed: _newText.text.trim().isEmpty ? null : _add,
                icon: const Icon(Icons.add_rounded),
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One consistent action: drag handle, the text (tap to edit in place;
/// Enter or leaving the field saves, a blank text restores the old one)
/// and a delete button.
class _ConsistentActionTile extends ConsumerStatefulWidget {
  final ConsistentAction action;
  final int index;
  final Color color;

  const _ConsistentActionTile({
    super.key,
    required this.action,
    required this.index,
    required this.color,
  });

  @override
  ConsumerState<_ConsistentActionTile> createState() =>
      _ConsistentActionTileState();
}

class _ConsistentActionTileState extends ConsumerState<_ConsistentActionTile> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEditing() {
    _controller.text = widget.action.text;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  Future<void> _commit() async {
    if (!_editing) return;
    final text = _controller.text.trim();
    setState(() => _editing = false);
    if (text.isEmpty || text == widget.action.text) return;
    await ref
        .read(projectServiceProvider)
        .editConsistentAction(widget.action.id, text);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: widget.index,
              child: Padding(
                key: ValueKey('consistent-action-handle-${a.id}'),
                padding: const EdgeInsets.all(12),
                child: Icon(
                  Icons.drag_indicator_rounded,
                  color: widget.color,
                  semanticLabel: 'Drag to reorder',
                ),
              ),
            ),
            Expanded(
              child: _editing
                  ? TextField(
                      key: ValueKey('consistent-action-edit-${a.id}'),
                      controller: _controller,
                      focusNode: _focus,
                      maxLength: consistentActionMaxLength,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _commit(),
                      decoration: const InputDecoration(
                        isDense: true,
                        counterText: '',
                      ),
                    )
                  : InkWell(
                      key: ValueKey('consistent-action-text-${a.id}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: _startEditing,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(a.text, style: theme.textTheme.bodyLarge),
                      ),
                    ),
            ),
            IconButton(
              key: ValueKey('consistent-action-delete-${a.id}'),
              tooltip: 'Delete',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => ref
                  .read(projectServiceProvider)
                  .deleteConsistentAction(a.id),
            ),
          ],
        ),
      ),
    );
  }
}
