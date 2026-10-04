import 'package:habit_quest/data/models/habit.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';

/// A habit with a reminder (default 08:30).
Habit reminderHabit({
  String id = 'h1',
  HabitSchedule schedule = const DailySchedule(),
  ReminderTime? reminderTime = const ReminderTime(hour: 8, minute: 30),
  DateTime? startDate,
  bool archived = false,
  String name = 'Drink water',
  String emoji = '💧',
}) =>
    Habit(
      id: id,
      name: name,
      emoji: emoji,
      colorValue: 0xFF4CC9F0,
      schedule: schedule,
      reminderTime: reminderTime,
      createdAt: startDate ?? DateTime(2026, 1, 1),
      startDate: startDate ?? DateTime(2026, 1, 1),
      archived: archived,
    );
