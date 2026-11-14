import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/utils/dates.dart';
import '../../projects/models/plan_task.dart';
import '../../projects/models/projects_data.dart';
import '../../projects/projects_providers.dart';
import '../../projects/ui/widgets/project_widgets.dart';

/// The plan tasks with a delivery date on [day], of non-archived projects,
/// in plan order.
List<PlanTask> tasksDueOn(ProjectsData data, DateTime day) => [
  for (final t in data.planTasks)
    if (t.deliveryDate != null &&
        isSameDay(t.deliveryDate!, day) &&
        _visible(data, t))
      t,
];

/// Delivery markers for the month grid: per `dateKey`, how many tasks are
/// due and how many of them are done.
Map<String, ({int due, int done})> taskMarkersByDay(ProjectsData data) {
  final out = <String, ({int due, int done})>{};
  for (final t in data.planTasks) {
    if (t.deliveryDate == null || !_visible(data, t)) continue;
    final k = dateKey(t.deliveryDate!);
    final m = out[k] ?? (due: 0, done: 0);
    out[k] = (due: m.due + 1, done: m.done + (t.done ? 1 : 0));
  }
  return out;
}

bool _visible(ProjectsData data, PlanTask t) {
  final target = data.target(t.targetId);
  if (target == null) return false;
  return !(data.project(target.projectId)?.archived ?? true);
}

/// The selected day's plan tasks (delivery date on [date]) with a
/// check-off, below the habits. Nothing when no task is due.
class DayTaskList extends ConsumerWidget {
  final DateTime date;

  const DayTaskList({super.key, required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(projectsDataProvider).value;
    if (data == null) return const SizedBox.shrink();
    final tasks = tasksDueOn(data, date);
    if (tasks.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('calendar-day-tasks'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
          child: Text('Tasks due 📦', style: theme.textTheme.titleLarge),
        ),
        for (final task in tasks) _TaskTile(task: task, data: data),
      ],
    );
  }
}

class _TaskTile extends ConsumerWidget {
  final PlanTask task;
  final ProjectsData data;

  const _TaskTile({required this.task, required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final target = data.target(task.targetId)!;
    final project = data.project(target.projectId);
    final color = projectColor(target.projectId);
    return Card(
      key: ValueKey('calendar-task-${task.id}'),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () =>
            context.push(AppRoutes.targetEditor(target.projectId, target.id)),
        leading: Checkbox(
          key: ValueKey('calendar-task-check-${task.id}'),
          value: task.done,
          activeColor: color,
          onChanged: (v) => ref
              .read(projectServiceProvider)
              .setPlanTaskDone(task.id, v ?? false),
        ),
        title: Text(
          task.title,
          style: theme.textTheme.titleMedium?.copyWith(
            decoration: task.done ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          '${target.title}${project == null ? '' : ' · ${project.name}'}',
          style: theme.textTheme.bodyMedium?.copyWith(color: color),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }
}
