/// Mapping between the local hive models and the API contract DTOs.
library;

import '../../core/utils/dates.dart';
import '../../data/models/check_in.dart';
import '../../data/models/habit.dart';
import '../../data/models/habit_schedule.dart';
import '../../data/remote/remote_models.dart';
import '../../data/sync/change_recorder.dart';
import '../projects/data/project_repository.dart';
import '../projects/models/consistent_action.dart';
import '../projects/models/plan_task.dart';
import '../projects/models/project.dart';
import '../projects/models/session_mark.dart';
import '../projects/models/target.dart';

/// The contract has no `startDate`; it travels inside the opaque
/// `schedule` object under this key (`HabitSchedule.fromJson` ignores it).
const startDateScheduleKey = 'startDate';

RemoteHabit habitToRemote(Habit h) => RemoteHabit(
  id: h.id,
  name: h.name,
  emoji: h.emoji,
  color: h.colorValue,
  schedule: {
    ...h.schedule.toJson(),
    startDateScheduleKey: dateKey(h.startDate),
  },
  reminderTime: h.reminderTime?.toString(),
  createdAt: h.createdAt.toUtc(),
  archived: h.archived,
  updatedAt: h.updatedAt,
  deletedAt: h.deletedAt,
);

Habit habitFromRemote(RemoteHabit r) {
  final createdAt = r.createdAt.toLocal();
  final start = r.schedule[startDateScheduleKey];
  return Habit(
    id: r.id,
    name: r.name,
    emoji: r.emoji,
    colorValue: r.color,
    schedule: HabitSchedule.fromJson(r.schedule),
    reminderTime: _parseReminder(r.reminderTime),
    createdAt: createdAt,
    startDate: _parseStart(start) ?? dateOnly(createdAt),
    archived: r.archived,
    updatedAt: r.updatedAt,
    deletedAt: r.deletedAt,
  );
}

RemoteCheckIn checkInToRemote(CheckIn c) => RemoteCheckIn(
  habitId: c.habitId,
  date: c.date,
  completed: c.completed,
  updatedAt: c.updatedAt,
  deletedAt: c.deletedAt,
);

CheckIn checkInFromRemote(RemoteCheckIn r) => CheckIn(
  habitId: r.habitId,
  date: r.date,
  completed: r.completed,
  updatedAt: r.updatedAt,
  deletedAt: r.deletedAt,
);

/// `schedule.startDate` (`yyyy-MM-dd`), or null when missing / malformed
/// (e.g. a habit written by a client that did not send it).
DateTime? _parseStart(Object? v) {
  if (v is! String) return null;
  try {
    return parseDateKey(v);
  } on FormatException {
    return null;
  }
}

ReminderTime? _parseReminder(String? s) {
  if (s == null) return null;
  final parts = s.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
    return null;
  }
  return ReminderTime(hour: h, minute: m);
}

// Projects -------------------------------------------------------------------
//
// The projects models' `toJson()` is the contract JSON (docs/PROJECTS.md
// "JSON shape"), so mapping is a straight (de)serialisation.

/// The sync queue type of each Projects resource.
SyncEntityType syncTypeOf(ProjectResource r) => switch (r) {
  ProjectResource.projects => SyncEntityType.project,
  ProjectResource.targets => SyncEntityType.target,
  ProjectResource.planTasks => SyncEntityType.planTask,
  ProjectResource.consistentActions => SyncEntityType.consistentAction,
  ProjectResource.sessionMarks => SyncEntityType.sessionMark,
};

/// `(actionId, date)` of a session mark key `actionId|yyyy-MM-dd`, or
/// `null` when malformed.
(String, DateTime)? parseSessionMarkKey(String key) {
  final i = key.lastIndexOf('|');
  if (i <= 0) return null;
  try {
    return (key.substring(0, i), parseDateKey(key.substring(i + 1)));
  } on FormatException {
    return null;
  }
}

/// The local record (tombstones included) of [resource] with [id] as
/// contract JSON, or `null` when unknown.
RemoteProjectRecord? localProjectRecord(
  ProjectRepository repo,
  ProjectResource resource,
  String id,
) {
  final Map<String, dynamic>? json = switch (resource) {
    ProjectResource.projects => repo.getProjectRecord(id)?.toJson(),
    ProjectResource.targets => repo.getTargetRecord(id)?.toJson(),
    ProjectResource.planTasks => repo.getPlanTaskRecord(id)?.toJson(),
    ProjectResource.consistentActions => repo.getActionRecord(id)?.toJson(),
    ProjectResource.sessionMarks => switch (parseSessionMarkKey(id)) {
      (final a, final d) => repo.getSessionMarkRecord(a, d)?.toJson(),
      null => null,
    },
  };
  return json == null ? null : RemoteProjectRecord.fromJson(resource, json);
}

/// Every local record id / key of [resource] (tombstones included).
Iterable<String> localProjectIds(
  ProjectRepository repo,
  ProjectResource resource,
) => switch (resource) {
  ProjectResource.projects => repo.getAllProjectRecords().map((x) => x.id),
  ProjectResource.targets => repo.getAllTargetRecords().map((x) => x.id),
  ProjectResource.planTasks => repo.getAllPlanTaskRecords().map((x) => x.id),
  ProjectResource.consistentActions => repo.getAllActionRecords().map(
    (x) => x.id,
  ),
  ProjectResource.sessionMarks => repo.getAllSessionMarkRecords().map(
    (x) => x.key,
  ),
};

/// Pulled records grouped into one [ProjectRecords] batch. Throws
/// (`FormatException`, `TypeError`, ...) on a record the models cannot read.
ProjectRecords projectRecordsFromRemote(Iterable<RemoteProjectRecord> records) {
  final projects = <Project>[];
  final targets = <Target>[];
  final planTasks = <PlanTask>[];
  final actions = <ConsistentAction>[];
  final marks = <SessionMark>[];
  for (final r in records) {
    switch (r.resource) {
      case ProjectResource.projects:
        projects.add(Project.fromJson(r.json));
      case ProjectResource.targets:
        targets.add(Target.fromJson(r.json));
      case ProjectResource.planTasks:
        planTasks.add(PlanTask.fromJson(r.json));
      case ProjectResource.consistentActions:
        actions.add(ConsistentAction.fromJson(r.json));
      case ProjectResource.sessionMarks:
        marks.add(SessionMark.fromJson(r.json));
    }
  }
  return ProjectRecords(
    projects: projects,
    targets: targets,
    planTasks: planTasks,
    actions: actions,
    sessionMarks: marks,
  );
}
