import 'package:habit_quest/features/projects/models/clock_time.dart';
import 'package:habit_quest/features/projects/models/consistent_action.dart';
import 'package:habit_quest/features/projects/models/goal.dart';
import 'package:habit_quest/features/projects/models/project.dart';
import 'package:habit_quest/features/projects/models/time_block.dart';

/// Fixed creation stamp (local midday so the local day is stable in any TZ).
DateTime createdOn(int y, int m, int d) => DateTime(y, m, d, 12);

Project project(String id, {String name = 'Project', bool archived = false}) =>
    Project(
      id: id,
      name: name,
      archived: archived,
      createdAt: createdOn(2026, 1, 1),
    );

Goal goal(
  String id, {
  String projectId = 'p1',
  String title = 'Goal',
  required DateTime deadline,
  GoalStatus status = GoalStatus.notStarted,
}) => Goal(
  id: id,
  projectId: projectId,
  title: title,
  deadline: deadline,
  status: status,
  createdAt: createdOn(2026, 1, 1),
);

ClockTime hm(String s) => ClockTime.parse(s);

TimeBlock weekly(
  String id, {
  String projectId = 'p1',
  String? label,
  required Set<int> days,
  String start = '10:00',
  String end = '13:00',
  DateTime? startDate,
  DateTime? endDate,
  DateTime? created,
}) => TimeBlock(
  id: id,
  projectId: projectId,
  label: label,
  startTime: hm(start),
  endTime: hm(end),
  recurrence: WeeklyRecurrence(days),
  startDate: startDate,
  endDate: endDate,
  createdAt: created ?? createdOn(2026, 1, 1),
);

TimeBlock monthly(
  String id, {
  String projectId = 'p1',
  String? label,
  required Set<int> days,
  String start = '10:00',
  String end = '13:00',
  DateTime? startDate,
  DateTime? endDate,
  DateTime? created,
}) => TimeBlock(
  id: id,
  projectId: projectId,
  label: label,
  startTime: hm(start),
  endTime: hm(end),
  recurrence: MonthlyRecurrence(days),
  startDate: startDate,
  endDate: endDate,
  createdAt: created ?? createdOn(2026, 1, 1),
);

ConsistentAction action(
  String id, {
  String goalId = 'g1',
  String text = 'Do it',
  int sortOrder = 0,
}) => ConsistentAction(
  id: id,
  goalId: goalId,
  text: text,
  sortOrder: sortOrder,
  createdAt: createdOn(2026, 1, 1),
);

const monFri = {1, 2, 3, 4, 5};
