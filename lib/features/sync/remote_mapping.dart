/// Mapping between the local hive models and the API contract DTOs.
library;

import '../../core/utils/dates.dart';
import '../../data/models/check_in.dart';
import '../../data/models/habit.dart';
import '../../data/models/habit_schedule.dart';
import '../../data/remote/remote_models.dart';

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
