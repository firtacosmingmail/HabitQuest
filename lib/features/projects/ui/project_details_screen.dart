import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/message_view.dart';
import '../../../domain/providers.dart';
import '../domain/overlap.dart';
import '../models/project.dart';
import '../models/session.dart';
import '../models/target.dart';
import '../projects_providers.dart';
import 'projects_screen.dart';
import 'widgets/project_widgets.dart';

/// How many past days of sessions can be marked from the details screen.
const recentSessionDays = 7;

/// How far ahead the upcoming sessions list looks.
const upcomingSessionDays = 14;

/// The most upcoming sessions listed.
const maxUpcomingSessions = 10;

/// Project details (`/projects/:id`): targets (deadline, status chip, plan
/// progress), the work split placeholder, recent sessions to mark attended
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
          // PLACEHOLDER (calendar task): replace WorkSplitPlaceholder with the
          // work split week view filtered to this project.
          WorkSplitPlaceholder(projectId: projectId),
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
    final progress = ref.watch(planProgressProvider(target.id));
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

/// PLACEHOLDER for the work split calendar (a separate task fills it with
/// the week view filtered to [projectId]). Keyed `work-split-placeholder`.
class WorkSplitPlaceholder extends StatelessWidget {
  final String projectId;

  const WorkSplitPlaceholder({super.key, required this.projectId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      key: const ValueKey('work-split-placeholder'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: scheme.outlineVariant, width: 2),
          color: scheme.primary.withValues(alpha: 0.04),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_week_rounded, color: scheme.primary, size: 32),
            const SizedBox(height: 6),
            Text(
              'Work split calendar coming soon',
              style: theme.textTheme.titleSmall,
            ),
          ],
        ),
      ),
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
