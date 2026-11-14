/// Riverpod providers for the projects feature (see docs/PROJECTS.md).
///
/// `main.dart` overrides [projectRepositoryProvider] with a
/// `HiveProjectRepository`; tests override it with
/// `InMemoryProjectRepository` (the test helpers do this by default).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/providers.dart';
import 'data/project_repository.dart';
import 'domain/project_events.dart';
import 'domain/project_service.dart';
import 'domain/sessions.dart';
import 'models/consistent_action.dart';
import 'models/plan_task.dart';
import 'models/project.dart';
import 'models/projects_data.dart';
import 'models/session.dart';
import 'models/target.dart';

/// Storage. Must be overridden (see `main.dart` / tests).
final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => throw UnimplementedError(
    'projectRepositoryProvider must be overridden in ProviderScope',
  ),
);

/// The single [ProjectService]; use it for every mutation.
final projectServiceProvider = Provider<ProjectService>((ref) {
  final service = ProjectService(
    ref.watch(projectRepositoryProvider),
    now: ref.watch(clockProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Every visible record (updates on each change).
final projectsDataProvider = StreamProvider<ProjectsData>(
  (ref) => ref.watch(projectRepositoryProvider).watchData(),
);

/// All projects, including archived, oldest first.
final projectsProvider = Provider<AsyncValue<List<Project>>>(
  (ref) => ref.watch(projectsDataProvider).whenData((d) => d.projects),
);

/// Non-archived projects.
final activeProjectsProvider = Provider<AsyncValue<List<Project>>>(
  (ref) => ref
      .watch(projectsProvider)
      .whenData((all) => all.where((p) => !p.archived).toList()),
);

/// Archived projects.
final archivedProjectsProvider = Provider<AsyncValue<List<Project>>>(
  (ref) => ref
      .watch(projectsProvider)
      .whenData((all) => all.where((p) => p.archived).toList()),
);

final projectByIdProvider = Provider.family<AsyncValue<Project?>, String>(
  (ref, id) => ref.watch(projectsDataProvider).whenData((d) => d.project(id)),
);

/// A project's targets, oldest first.
final targetsOfProjectProvider =
    Provider.family<AsyncValue<List<Target>>, String>(
  (ref, projectId) =>
      ref.watch(projectsDataProvider).whenData((d) => d.targetsOf(projectId)),
);

final targetByIdProvider = Provider.family<AsyncValue<Target?>, String>(
  (ref, id) => ref.watch(projectsDataProvider).whenData((d) => d.target(id)),
);

/// A target's plan, in `position` order.
final planTasksOfTargetProvider =
    Provider.family<AsyncValue<List<PlanTask>>, String>(
  (ref, targetId) =>
      ref.watch(projectsDataProvider).whenData((d) => d.planTasksOf(targetId)),
);

/// A target's consistent actions, oldest first.
final actionsOfTargetProvider =
    Provider.family<AsyncValue<List<ConsistentAction>>, String>(
  (ref, targetId) =>
      ref.watch(projectsDataProvider).whenData((d) => d.actionsOf(targetId)),
);

/// Plan progress for display only (never drives the status).
final planProgressProvider =
    Provider.family<({int done, int total}), String>((ref, targetId) {
  final tasks = ref.watch(planTasksOfTargetProvider(targetId)).value ?? [];
  return (done: tasks.where((t) => t.done).length, total: tasks.length);
});

/// A date range for [sessionsProvider]; bounds are normalised to dates
/// and inclusive. Optional [projectId] / [targetId] narrow the result.
typedef SessionQuery = ({
  DateTime from,
  DateTime to,
  String? projectId,
  String? targetId,
});

/// Every session in the query's range (all projects, done targets and
/// archived projects included), with attended marks, sorted by date and
/// start time. Pass `dateOnly(...)` bounds so the family key is stable.
final sessionsProvider =
    Provider.family<AsyncValue<List<Session>>, SessionQuery>((ref, q) {
  return ref.watch(projectsDataProvider).whenData((d) {
    final all = sessionsInRange(d, from: q.from, to: q.to);
    return all
        .where((s) =>
            (q.projectId == null || s.projectId == q.projectId) &&
            (q.targetId == null || s.targetId == q.targetId))
        .toList();
  });
});

/// Today's sessions (all projects).
final todaySessionsProvider = Provider<AsyncValue<List<Session>>>((ref) {
  final today = ref.watch(todayProvider);
  return ref.watch(sessionsProvider(
      (from: today, to: today, projectId: null, targetId: null)));
});

/// Local projects changes (after persistence).
final projectChangesProvider = Provider<Stream<ProjectChangeEvent>>(
  (ref) => ref.watch(projectServiceProvider).changes,
);

/// Changes that arrived through sync or a local wipe.
final remoteProjectChangesProvider = Provider<Stream<ProjectChangeEvent>>(
  (ref) => ref.watch(projectServiceProvider).remoteChanges,
);

/// Attended marks set / removed by the user (XP).
final sessionAttendanceEventsProvider =
    Provider<Stream<SessionAttendanceEvent>>(
  (ref) => ref.watch(projectServiceProvider).attendanceEvents,
);
