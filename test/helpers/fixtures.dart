import 'package:habit_quest/data/models/completion_log.dart';
import 'package:habit_quest/data/models/habit.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';

/// Shorthand for a local date.
DateTime d(int y, int m, int day) => DateTime(y, m, day);

Habit habit({
  String id = 'h1',
  HabitSchedule schedule = const DailySchedule(),
  DateTime? startDate,
  bool archived = false,
  String name = 'Drink water',
}) =>
    Habit(
      id: id,
      name: name,
      emoji: '💧',
      colorValue: 0xFF4CC9F0,
      schedule: schedule,
      createdAt: startDate ?? d(2026, 1, 1),
      startDate: startDate ?? d(2026, 1, 1),
      archived: archived,
    );

CompletionLog log(Map<String, List<DateTime>> dates) =>
    CompletionLog.fromDates(dates);

/// All dates from [from] to [to] inclusive.
List<DateTime> range(DateTime from, DateTime to) => [
      for (var x = from; !x.isAfter(to); x = DateTime(x.year, x.month, x.day + 1))
        x,
    ];
