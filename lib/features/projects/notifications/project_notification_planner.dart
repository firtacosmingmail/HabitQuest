/// Pure planning logic: projects snapshot → one-shot notification requests.
///
/// The OS keeps the requests; this file only decides *which* and *when*
/// (see README "Projects notifications").
library;

import '../../../core/utils/dates.dart';
import '../../notifications/reminder_ids.dart';
import '../../notifications/reminder_request.dart';
import '../domain/sessions.dart';
import '../models/projects_data.dart';
import 'project_notification_messages.dart';
import 'project_notification_settings.dart';

/// Rolling window: only notifications firing within the next 14 days are
/// scheduled. The window is refreshed on app start / resume and on every
/// change, so later ones are added as time passes.
const kProjectNotificationWindow = Duration(days: 14);

/// At most this many Projects notifications are pending at once (nearest
/// first). iOS keeps only 64 pending notifications per app, shared with the
/// habit reminders; 32 leaves the other half for habits (a daily habit uses
/// 1, a weekdays habit up to 7, an every-N-days habit 12).
const kProjectNotificationCap = 32;

/// Deadline reminders and task deliveries fire at this local time.
const kProjectMorningHour = 9;
const kProjectMorningMinute = 0;

/// Days before a deadline on which a reminder fires (0 = deadline morning).
const kDeadlineReminderDays = [3, 1, 0];

/// Days before a delivery date on which a task reminder fires.
const kTaskDeliveryReminderDays = 1;

/// Payload prefix, so a tap handler can tell projects from habits
/// (`ReminderRequest.habitId` is the payload).
const kProjectPayloadPrefix = 'project:';

enum ProjectNotificationKind { workSplit, deadline, taskDelivery }

/// Notification id for a stable [key] (e.g. `split|<actionId>|2026-11-20`):
/// `kProjectNotificationIdBase + fnv1a(key) & 0x3FFFFFFF`, i.e. always in
/// `[2^30, 2^31)`, never in the habit range.
int projectNotificationId(String key) =>
    kProjectNotificationIdBase + (stableHash(key) & 0x3FFFFFFF);

/// Whether [id] is in the Projects notification range.
bool isProjectNotificationId(int id) =>
    id >= kProjectNotificationIdBase && id < (1 << 31);

/// One planned Projects notification.
class ProjectNotification {
  final ProjectNotificationKind kind;

  /// Stable identity of the occurrence; the id is derived from it.
  final String key;
  final String projectId;
  final DateTime fireAt;
  final String title;
  final String body;

  const ProjectNotification({
    required this.kind,
    required this.key,
    required this.projectId,
    required this.fireAt,
    required this.title,
    required this.body,
  });

  int get id => projectNotificationId(key);

  ReminderRequest toRequest() => ReminderRequest(
        id: id,
        habitId: '$kProjectPayloadPrefix$projectId',
        slot: 0,
        title: title,
        body: body,
        repeat: ReminderRepeat.once,
        firstFire: fireAt,
      );

  @override
  String toString() =>
      'ProjectNotification(${kind.name}, $key @ $fireAt)';
}

/// Plans the Projects notifications as of [now] (local time).
///
/// * Skips archived projects, targets marked done (their sessions,
///   deadline and tasks) and plan tasks marked done.
/// * Work split: at each session's start (sessions already marked
///   attended are skipped).
/// * Deadline: 3 days before, 1 day before and on the deadline day, at
///   09:00.
/// * Task delivery: the day before the delivery date, at 09:00.
/// * Only times strictly after [now] and within [window]; sorted by fire
///   time (then key) and capped at [cap], nearest first.
List<ProjectNotification> planProjectNotifications(
  ProjectsData data, {
  required DateTime now,
  required ProjectNotificationSettings settings,
  Duration window = kProjectNotificationWindow,
  int cap = kProjectNotificationCap,
}) {
  final until = now.add(window);
  bool inWindow(DateTime t) => t.isAfter(now) && !t.isAfter(until);
  DateTime morning(DateTime day) => DateTime(
      day.year, day.month, day.day, kProjectMorningHour, kProjectMorningMinute);

  final out = <ProjectNotification>[];

  bool projectActive(String projectId) {
    final p = data.project(projectId);
    return p != null && !p.archived;
  }

  if (settings.workSplits) {
    final sessions = sessionsInRange(
      data,
      from: dateOnly(now),
      to: dateOnly(until),
      includeDoneTargets: false,
      includeArchivedProjects: false,
    );
    for (final s in sessions) {
      if (s.attended || !inWindow(s.start)) continue;
      final target = data.target(s.targetId)!;
      final project = data.project(s.projectId)!;
      final key = 'split|${s.key}';
      final seed = stableHash(key);
      final values = {
        'project': project.name,
        'target': target.title,
        'time': '${s.startTime}',
      };
      out.add(ProjectNotification(
        kind: ProjectNotificationKind.workSplit,
        key: key,
        projectId: project.id,
        fireAt: s.start,
        title: fill(pick(kWorkSplitTitles, seed), values),
        body: fill(pick(kWorkSplitBodies, seed >> 3), values),
      ));
    }
  }

  if (settings.deadlines) {
    for (final t in data.targets) {
      if (t.isDone || !projectActive(t.projectId)) continue;
      final project = data.project(t.projectId)!;
      for (final daysBefore in kDeadlineReminderDays) {
        final at = morning(addDays(t.deadline, -daysBefore));
        if (!inWindow(at)) continue;
        final key = 'deadline|${t.id}|$daysBefore';
        final seed = stableHash(key);
        final values = {'project': project.name, 'target': t.title};
        out.add(ProjectNotification(
          kind: ProjectNotificationKind.deadline,
          key: key,
          projectId: project.id,
          fireAt: at,
          title: fill(pick(kDeadlineTitles[daysBefore]!, seed), values),
          body: fill(pick(kDeadlineBodies, seed >> 3), values),
        ));
      }
    }
  }

  if (settings.taskDeliveries) {
    for (final task in data.planTasks) {
      final delivery = task.deliveryDate;
      if (task.done || delivery == null) continue;
      final target = data.target(task.targetId);
      if (target == null || target.isDone) continue;
      if (!projectActive(target.projectId)) continue;
      final project = data.project(target.projectId)!;
      final at = morning(addDays(delivery, -kTaskDeliveryReminderDays));
      if (!inWindow(at)) continue;
      final key = 'task|${task.id}';
      final seed = stableHash(key);
      final values = {
        'project': project.name,
        'target': target.title,
        'task': task.title,
      };
      out.add(ProjectNotification(
        kind: ProjectNotificationKind.taskDelivery,
        key: key,
        projectId: project.id,
        fireAt: at,
        title: fill(pick(kTaskDeliveryTitles, seed), values),
        body: fill(pick(kTaskDeliveryBodies, seed >> 3), values),
      ));
    }
  }

  out.sort((a, b) {
    final c = a.fireAt.compareTo(b.fireAt);
    return c != 0 ? c : a.key.compareTo(b.key);
  });
  // Nearest first; an (astronomically unlikely) id collision keeps the
  // earlier notification.
  final ids = <int>{};
  final capped = <ProjectNotification>[];
  for (final n in out) {
    if (capped.length >= cap) break;
    if (ids.add(n.id)) capped.add(n);
  }
  return capped;
}
