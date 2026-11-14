import 'package:habit_quest/features/projects/models/clock_time.dart';
import 'package:habit_quest/features/projects/models/consistent_action.dart';
import 'package:habit_quest/features/projects/models/project.dart';
import 'package:habit_quest/features/projects/models/target.dart';

/// Fixed creation stamp (local midday so the local day is stable in any TZ).
DateTime createdOn(int y, int m, int d) => DateTime(y, m, d, 12);

Project project(String id, {String name = 'Project', bool archived = false}) =>
    Project(
      id: id,
      name: name,
      archived: archived,
      createdAt: createdOn(2026, 1, 1),
    );

Target target(
  String id, {
  String projectId = 'p1',
  String title = 'Target',
  required DateTime deadline,
  TargetStatus status = TargetStatus.notStarted,
}) => Target(
  id: id,
  projectId: projectId,
  title: title,
  deadline: deadline,
  status: status,
  createdAt: createdOn(2026, 1, 1),
);

ClockTime hm(String s) => ClockTime.parse(s);

ConsistentAction weekly(
  String id, {
  String targetId = 't1',
  required Set<int> days,
  String start = '10:00',
  String end = '13:00',
  DateTime? startDate,
  DateTime? created,
}) => ConsistentAction(
  id: id,
  targetId: targetId,
  startTime: hm(start),
  endTime: hm(end),
  recurrence: WeeklyRecurrence(days),
  startDate: startDate,
  createdAt: created ?? createdOn(2026, 1, 1),
);

ConsistentAction monthly(
  String id, {
  String targetId = 't1',
  required Set<int> days,
  String start = '10:00',
  String end = '13:00',
  DateTime? startDate,
  DateTime? created,
}) => ConsistentAction(
  id: id,
  targetId: targetId,
  startTime: hm(start),
  endTime: hm(end),
  recurrence: MonthlyRecurrence(days),
  startDate: startDate,
  createdAt: created ?? createdOn(2026, 1, 1),
);

const monFri = {1, 2, 3, 4, 5};
