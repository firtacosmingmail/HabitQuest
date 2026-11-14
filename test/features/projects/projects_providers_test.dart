import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/domain/providers.dart';
import 'package:habit_quest/features/projects/data/project_repository.dart';
import 'package:habit_quest/features/projects/models/consistent_action.dart';
import 'package:habit_quest/features/projects/projects_providers.dart';

import 'helpers.dart';

void main() {
  test('providers follow the service', () async {
    final container = ProviderContainer(
      overrides: [
        projectRepositoryProvider.overrideWithValue(
          InMemoryProjectRepository(),
        ),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 16, 9)),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(projectsDataProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(projectsDataProvider.future);

    final service = container.read(projectServiceProvider);
    final p = await service.createProject(name: 'Content business');
    final archived = await service.createProject(name: 'Old');
    await service.archiveProject(archived.id);
    final t = await service.createTarget(
      projectId: p.id,
      title: '5 videos',
      deadline: DateTime(2026, 11, 30),
    );
    final k = await service.addPlanTask(targetId: t.id, title: 'Scripts');
    await service.addPlanTask(targetId: t.id, title: 'Edits');
    await service.setPlanTaskDone(k.id, true);
    final a = await service.createAction(
      targetId: t.id,
      startTime: hm('10:00'),
      endTime: hm('13:00'),
      recurrence: WeeklyRecurrence(monFri),
    );
    await service.setSessionAttended(a.id, DateTime(2026, 11, 16), true);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(projectsProvider).value, hasLength(2));
    expect(container.read(activeProjectsProvider).value!.single.id, p.id);
    expect(
      container.read(archivedProjectsProvider).value!.single.id,
      archived.id,
    );
    expect(
      container.read(projectByIdProvider(p.id)).value?.name,
      'Content business',
    );
    expect(container.read(targetsOfProjectProvider(p.id)).value, [t]);
    expect(container.read(targetByIdProvider(t.id)).value, t);
    expect(container.read(planTasksOfTargetProvider(t.id)).value, hasLength(2));
    expect(container.read(planProgressProvider(t.id)), (done: 1, total: 2));
    expect(container.read(actionsOfTargetProvider(t.id)).value, [a]);

    final today = container.read(todaySessionsProvider).value!;
    expect(today.single.attended, isTrue);
    final week = container
        .read(
          sessionsProvider((
            from: DateTime(2026, 11, 16),
            to: DateTime(2026, 11, 22),
            projectId: p.id,
            targetId: null,
          )),
        )
        .value!;
    expect(week, hasLength(5));
    final none = container
        .read(
          sessionsProvider((
            from: DateTime(2026, 11, 16),
            to: DateTime(2026, 11, 22),
            projectId: archived.id,
            targetId: null,
          )),
        )
        .value!;
    expect(none, isEmpty);
  });
}
