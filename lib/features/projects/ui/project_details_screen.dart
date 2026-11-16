import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/message_view.dart';
import '../../../domain/providers.dart';
import '../domain/overlap.dart';
import '../models/project.dart';
import '../models/session.dart';
import '../models/target.dart';
import '../projects_providers.dart';
import 'projects_screen.dart';
import 'work_split_view.dart';
import 'widgets/project_widgets.dart';

/// How many past days of sessions can be marked from the details screen.
const recentSessionDays = 7;

/// How far ahead the upcoming sessions list looks.
const upcomingSessionDays = 14;

/// The most upcoming sessions listed.
const maxUpcomingSessions = 10;

/// Project details (`/projects/:id`): targets (deadline, status chip, plan
/// progress), the work split (week view of this project's blocks), recent sessions to mark attended
/// and upcoming sessions.
class ProjectDetailsScreen extends ConsumerWidget {
  final String projectId;

  const ProjectDetailsScreen({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(projectByIdProvider(projectId));
    final project = projectAsync.value;

    if (!projectAsync.hasValue) {
      return Scaffold(
        appBar: AppBar(),
        body: projectAsync.hasError
            ? MessageView(
                emoji: '😵',
                title: 'Something went wrong',
                message: '${projectAsync.error}',
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    if (project == null) {
      return Scaffold(
        appBar: AppBar(),
        body: MessageView(
          key: const ValueKey('project-not-found'),
          emoji: '🔭',
          title: 'Project not found',
          message: 'It may have been deleted.',
          action: FilledButton.icon(
            onPressed: () => context.go(AppRoutes.projects),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Back to projects'),
          ),
        ),
      );
    }

    final targets =
        ref.watch(targetsOfProjectProvider(projectId)).value ??
        const <Target>[];
    final color = projectColor(projectId);

    return Scaffold(
      appBar: AppBar(
        title: Text(project.name),
        actions: [
          ProjectMenuButton(
            project: project,
            onDeleted: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(AppRoutes.projects);
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('new-target-fab'),
        onPressed: () => context.push(AppRoutes.newTarget(projectId)),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New target'),
      ),
      body: ListView(
        key: const ValueKey('project-details-list'),
        padding: const EdgeInsets.only(bottom: 112),
        children: [
          if (project.archived) _ArchivedBanner(project: project),
          const SectionTitle('Targets'),
          if (targets.isEmpty)
            const NoteText('No targets yet. Add one with a deadline 🎯')
          else
            for (final t in targets) TargetTile(target: t, color: color),
          const SectionTitle('Work split'),
          ProjectWorkSplit(projectId: projectId),
          _SessionsSection(project: project, targets: targets, color: color),
        ],
      ),
    );
  }
}

class _ArchivedBanner extends ConsumerWidget {
  final Project project;

  const _ArchivedBanner({required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: ListTile(
        leading: const Icon(Icons.archive_rounded),
        title: const Text('Archived'),
        subtitle: const Text('Its time blocks still block clashing times.'),
        trailing: TextButton(
          onPressed: () => ref
              .read(projectServiceProvider)
              .archiveProject(project.id, archived: false),
          child: const Text('Unarchive'),
        ),
      ),
    );
  }
}

/// `Due in 3 days`, `Due today`, `2 days overdue`.
String deadlineText(DateTime deadline, DateTime today) {
  final days = daysBetween(today, deadline);
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  if (days > 1) return 'Due in $days days';
  return days == -1 ? '1 day overdue' : '${-days} days overdue';
}

/// Sets a target's status (manual) and shows a refused change (a clash
/// when reopening a done target) in a dialog.
Future<void> changeTargetStatus(
  BuildContext context,
  WidgetRef ref,
  Target target,
  TargetStatus status,
) async {
  try {
    await ref.read(projectServiceProvider).setTargetStatus(target.id, status);
  } on ActionOverlapException catch (e) {
    if (context.mounted) await showOverlapDialog(context, e.message);
  }
}

/// A target on the details screen: title, deadline, status chip (tap to
/// change) and plan progress. Tapping opens the target editor.
class TargetTile extends ConsumerWidget {
  final Target target;
  final Color color;

  const TargetTile({super.key, required this.target, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final progress = watchPlanProgress(ref, target.id);
    final overdue = !target.isDone && target.deadline.isBefore(today);
    return Card(
      key: ValueKey('target-tile-${target.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            context.push(AppRoutes.targetEditor(target.projectId, target.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      target.title,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  TargetStatusChip(
                    key: ValueKey('status-chip-${target.id}'),
                    status: target.status,
                    onChanged: (s) =>
                        changeTargetStatus(context, ref, target, s),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.flag_rounded,
                    size: 16,
                    color: overdue ? theme.colorScheme.error : color,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${longDate(target.deadline)} · '
                      '${target.isDone ? 'Done' : deadlineText(target.deadline, today)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: overdue
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              PlanProgressBar(
                done: progress.done,
                total: progress.total,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Largest fitted grid height of the work split card on the details screen.
const projectWorkSplitGridHeight = 340.0;

/// The [WorkSplitView] filtered to [projectId], in a card. The automatic
/// hour range fits a grid of about 45% of the screen height (200–340 px);
/// "Earlier" / "Later" add rows at that same height, so the card grows
/// (the details screen scrolls).
class ProjectWorkSplit extends StatelessWidget {
  final String projectId;

  const ProjectWorkSplit({super.key, required this.projectId});

  @override
  Widget build(BuildContext context) {
    final gridHeight = (MediaQuery.sizeOf(context).height * 0.45).clamp(
      200.0,
      projectWorkSplitGridHeight,
    );
    return Card(
      key: const ValueKey('project-work-split'),
      clipBehavior: Clip.antiAlias,
      child: WorkSplitView(projectId: projectId, gridHeight: gridHeight),
    );
  }
}

class _SessionsSection extends ConsumerWidget {
  final Project project;
  final List<Target> targets;
  final Color color;

  const _SessionsSection({
    required this.project,
    required this.targets,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final sessions =
        ref
            .watch(
              sessionsProvider((
                from: addDays(today, -recentSessionDays),
                to: addDays(today, upcomingSessionDays),
                projectId: project.id,
                targetId: null,
              )),
            )
            .value ??
        const <Session>[];
    final byId = {for (final t in targets) t.id: t};

    // Today's and past sessions, newest first (they can be marked).
    final recent = sessions.where((s) => !s.date.isAfter(today)).toList()
      ..sort((a, b) {
        final c = b.date.compareTo(a.date);
        return c != 0 ? c : a.startTime.compareTo(b.startTime);
      });
    // Upcoming: skip done targets (their blocks no longer count).
    final upcoming = sessions
        .where(
          (s) => s.date.isAfter(today) && !(byId[s.targetId]?.isDone ?? true),
        )
        .take(maxUpcomingSessions)
        .toList();

    String title(Session s) => byId[s.targetId]?.title ?? 'Target';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Sessions'),
        if (recent.isEmpty)
          const NoteText('No sessions today or in the past week.')
        else
          for (final s in recent)
            SessionTile(
              key: ValueKey('session-${s.key}'),
              session: s,
              targetTitle: title(s),
              color: color,
              canAttend: true,
            ),
        const SectionTitle('Upcoming'),
        if (upcoming.isEmpty)
          const NoteText('No upcoming sessions. Add a time block to a target ⏰')
        else
          for (final s in upcoming)
            SessionTile(
              key: ValueKey('session-${s.key}'),
              session: s,
              targetTitle: title(s),
              color: color,
              canAttend: false,
            ),
      ],
    );
  }
}
