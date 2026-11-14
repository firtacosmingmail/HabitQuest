import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/widgets/message_view.dart';
import '../models/project.dart';
import '../models/target.dart';
import '../projects_providers.dart';
import 'widgets/project_widgets.dart';

/// Projects tab (`/projects`): active projects with their targets'
/// progress, and an "Archived" section (archived projects still block
/// clashing times). Create / rename / archive / delete from here.
class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The base stream only (not activeProjectsProvider, which derives from
    // another derived provider): this tab sits under pushed routes, see the
    // note in lib/domain/providers.dart.
    final data = ref.watch(projectsDataProvider);
    final active = data.whenData(
      (d) => d.projects.where((p) => !p.archived).toList(),
    );

    final Widget body;
    if (active.hasError) {
      body = MessageView(
        emoji: '😵',
        title: 'Something went wrong',
        message: 'Your projects could not be loaded.\n${active.error}',
      );
    } else if (!active.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final activeList = active.requireValue;
      final archivedList = data.requireValue.projects
          .where((p) => p.archived)
          .toList();
      body = ListView(
        key: const ValueKey('projects-list'),
        padding: const EdgeInsets.only(bottom: 112),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              'Projects 🚀',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          if (activeList.isEmpty)
            MessageView(
              emoji: '🗺️',
              title: archivedList.isEmpty
                  ? 'Plan your first big quest'
                  : 'No active projects',
              message:
                  'A project holds targets with deadlines, a plan and regular time blocks.',
              action: FilledButton.icon(
                key: const ValueKey('empty-create-project'),
                onPressed: () => createProjectFlow(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New project'),
              ),
            )
          else
            for (final p in activeList) ProjectCard(project: p),
          if (archivedList.isNotEmpty) ...[
            const SectionTitle('Archived'),
            const NoteText(
              'Archived projects keep their time blocks: they still block clashing times.',
            ),
            for (final p in archivedList) ProjectCard(project: p),
          ],
        ],
      );
    }

    final hasProjects = active.value?.isNotEmpty ?? false;
    return Scaffold(
      body: SafeArea(bottom: false, child: body),
      floatingActionButton: hasProjects
          ? FloatingActionButton.extended(
              key: const ValueKey('new-project-fab'),
              onPressed: () => createProjectFlow(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New project'),
            )
          : null,
    );
  }
}

/// Asks for a name and creates the project.
Future<void> createProjectFlow(BuildContext context, WidgetRef ref) async {
  final name = await textDialog(
    context,
    title: 'New project',
    label: 'Project name',
    confirmLabel: 'Create',
  );
  if (name == null) return;
  await ref.read(projectServiceProvider).createProject(name: name);
}

enum _ProjectMenu { rename, archive, unarchive, delete }

/// Runs the rename / archive / delete actions shared by the list card and
/// the details app bar. Returns `true` when the project was deleted.
Future<bool> runProjectMenuAction(
  BuildContext context,
  WidgetRef ref,
  Project project,
  String action,
) async {
  final service = ref.read(projectServiceProvider);
  switch (action) {
    case 'rename':
      final name = await textDialog(
        context,
        title: 'Rename project',
        label: 'Project name',
        initial: project.name,
        confirmLabel: 'Save',
      );
      if (name != null) await service.renameProject(project.id, name);
    case 'archive':
      await service.archiveProject(project.id);
    case 'unarchive':
      await service.archiveProject(project.id, archived: false);
    case 'delete':
      final ok = await confirmDialog(
        context,
        title: 'Delete “${project.name}”?',
        message:
            'Its targets, plans and time blocks are deleted too. This cannot be undone.',
        confirmLabel: 'Delete',
      );
      if (ok) {
        await service.deleteProject(project.id);
        return true;
      }
  }
  return false;
}

/// Popup menu with rename / archive or unarchive / delete.
class ProjectMenuButton extends ConsumerWidget {
  final Project project;
  final VoidCallback? onDeleted;

  const ProjectMenuButton({super.key, required this.project, this.onDeleted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_ProjectMenu>(
      key: ValueKey('project-menu-${project.id}'),
      tooltip: 'Project actions',
      onSelected: (m) async {
        final deleted = await runProjectMenuAction(
          context,
          ref,
          project,
          m.name,
        );
        if (deleted) onDeleted?.call();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          key: ValueKey('project-rename'),
          value: _ProjectMenu.rename,
          child: ListTile(
            leading: Icon(Icons.edit_rounded),
            title: Text('Rename'),
          ),
        ),
        if (project.archived)
          const PopupMenuItem(
            key: ValueKey('project-unarchive'),
            value: _ProjectMenu.unarchive,
            child: ListTile(
              leading: Icon(Icons.unarchive_rounded),
              title: Text('Unarchive'),
            ),
          )
        else
          const PopupMenuItem(
            key: ValueKey('project-archive'),
            value: _ProjectMenu.archive,
            child: ListTile(
              leading: Icon(Icons.archive_rounded),
              title: Text('Archive'),
            ),
          ),
        const PopupMenuItem(
          key: ValueKey('project-delete'),
          value: _ProjectMenu.delete,
          child: ListTile(
            leading: Icon(Icons.delete_rounded),
            title: Text('Delete'),
          ),
        ),
      ],
    );
  }
}

/// A project in the list: name, menu and one progress row per target.
class ProjectCard extends ConsumerWidget {
  final Project project;

  const ProjectCard({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = projectColor(project.id);
    final targets =
        ref.watch(targetsOfProjectProvider(project.id)).value ??
        const <Target>[];
    final done = targets.where((t) => t.isDone).length;

    return Card(
      key: ValueKey('project-card-${project.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.projectDetails(project.id)),
        child: Opacity(
          opacity: project.archived ? 0.7 : 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: color.withValues(alpha: 0.18),
                      child: Icon(
                        Icons.rocket_launch_rounded,
                        color: color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(project.name, style: theme.textTheme.titleLarge),
                          Text(
                            targets.isEmpty
                                ? 'No targets yet'
                                : '$done of ${targets.length} '
                                      '${targets.length == 1 ? 'target' : 'targets'} done',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ProjectMenuButton(project: project),
                  ],
                ),
                for (final t in targets)
                  Padding(
                    padding: const EdgeInsets.only(top: 10, right: 12),
                    child: _TargetProgressRow(target: t, color: color),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TargetProgressRow extends ConsumerWidget {
  final Target target;
  final Color color;

  const _TargetProgressRow({required this.target, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = watchPlanProgress(ref, target.id);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                target.title,
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            TargetStatusChip(status: target.status),
          ],
        ),
        const SizedBox(height: 4),
        PlanProgressBar(
          done: progress.done,
          total: progress.total,
          color: color,
        ),
      ],
    );
  }
}
