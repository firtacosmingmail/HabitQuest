import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/domain/providers.dart';
import 'package:habit_quest/features/projects/data/project_repository.dart';
import 'package:habit_quest/features/projects/models/time_block.dart';
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
    final g = await service.createGoal(
      projectId: p.id,
      title: '5 videos',
      deadline: DateTime(2026, 11, 30),
    );
    final k = await service.addPlanTask(goalId: g.id, title: 'Scripts');
    await service.addPlanTask(goalId: g.id, title: 'Edits');
    await service.setPlanTaskDone(k.id, true);
    final b = await service.createTimeBlock(
      projectId: p.id,
      label: 'Editing',
      startTime: hm('10:00'),
      endTime: hm('13:00'),
      recurrence: WeeklyRecurrence(monFri),
    );
    await service.setSessionAttended(b.id, DateTime(2026, 11, 16), true);
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
    expect(container.read(goalsOfProjectProvider(p.id)).value, [g]);
    expect(container.read(goalByIdProvider(g.id)).value, g);
    expect(container.read(planTasksOfGoalProvider(g.id)).value, hasLength(2));
    expect(container.read(planProgressProvider(g.id)), (done: 1, total: 2));
    expect(container.read(timeBlocksOfProjectProvider(p.id)).value, [b]);
    expect(
      container.read(timeBlocksOfProjectProvider(archived.id)).value,
      isEmpty,
    );
    expect(container.read(timeBlockByIdProvider(b.id)).value, b);

    final today = container.read(todaySessionsProvider).value!;
    expect(today.single.attended, isTrue);
    expect(today.single.label, 'Editing');
    final week = container
        .read(
          sessionsProvider((
            from: DateTime(2026, 11, 16),
            to: DateTime(2026, 11, 22),
            projectId: p.id,
            timeBlockId: null,
          )),
        )
        .value!;
    expect(week, hasLength(5));
    final byBlock = container
        .read(
          sessionsProvider((
            from: DateTime(2026, 11, 16),
            to: DateTime(2026, 11, 22),
            projectId: null,
            timeBlockId: b.id,
          )),
        )
        .value!;
    expect(byBlock, hasLength(5));
    final none = container
        .read(
          sessionsProvider((
            from: DateTime(2026, 11, 16),
            to: DateTime(2026, 11, 22),
            projectId: archived.id,
            timeBlockId: null,
          )),
        )
        .value!;
    expect(none, isEmpty);
  });

  test('consistent actions of a goal follow sortOrder', () async {
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
    final g = await service.createGoal(
      projectId: p.id,
      title: '5 videos',
      deadline: DateTime(2026, 11, 30),
    );
    final other = await service.createGoal(
      projectId: p.id,
      title: 'Other',
      deadline: DateTime(2026, 12, 31),
    );
    final a = await service.addConsistentAction(goalId: g.id, text: 'A');
    final b = await service.addConsistentAction(goalId: g.id, text: 'B');
    final c = await service.addConsistentAction(goalId: g.id, text: 'C');
    await service.addConsistentAction(goalId: other.id, text: 'Elsewhere');
    await Future<void>.delayed(Duration.zero);

    List<String> texts() => container
        .read(consistentActionsOfGoalProvider(g.id))
        .value!
        .map((x) => x.text)
        .toList();

    expect(texts(), ['A', 'B', 'C']);
    await service.reorderConsistentActions(g.id, [c.id, a.id, b.id]);
    await Future<void>.delayed(Duration.zero);
    expect(texts(), ['C', 'A', 'B']);
    await service.deleteConsistentAction(a.id);
    await Future<void>.delayed(Duration.zero);
    expect(texts(), ['C', 'B']);
    expect(
      container
          .read(consistentActionsOfGoalProvider(other.id))
          .value!
          .single
          .text,
      'Elsewhere',
    );
  });
}
