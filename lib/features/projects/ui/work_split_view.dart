/// The work split: a Monday-first week view with hour rows and a time block
/// per consistent-action session, coloured per project and labelled with
/// the target. Used by the Calendar tab (all projects) and by the project
/// details (filtered with [WorkSplitView.projectId]).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/providers.dart';
import '../domain/sessions.dart';
import '../models/projects_data.dart';
import '../models/session.dart';
import '../models/target.dart';
import '../projects_providers.dart';
import 'widgets/project_widgets.dart';
import '../../habits/widgets/check_in_button.dart';

/// Height of one hour row (logical pixels).
const workSplitHourHeight = 48.0;

/// Hour the grid scrolls to when the week has no sessions.
const workSplitDefaultStartHour = 8;

/// Width of the hour labels column.
const _gutterWidth = 40.0;

/// The sessions shown in the week starting [weekStart] (Monday): every
/// session of the week, except sessions of archived projects (unless
/// [projectId] is given) and FUTURE sessions of targets marked done (their
/// time is free again; past ones stay, attended or not).
List<Session> workSplitSessions(
  ProjectsData data, {
  required DateTime weekStart,
  required DateTime today,
  String? projectId,
}) {
  final sessions = sessionsInRange(
    data,
    from: weekStart,
    to: addDays(weekStart, 6),
  );
  return [
    for (final s in sessions)
      if ((projectId == null
              ? !(data.project(s.projectId)?.archived ?? true)
              : s.projectId == projectId) &&
          !(s.date.isAfter(today) && (data.target(s.targetId)?.isDone ?? true)))
        s,
  ];
}

/// The targets whose deadline falls on [day] (same filter as the blocks).
List<Target> deadlinesOn(
  ProjectsData data,
  DateTime day, {
  String? projectId,
}) => [
  for (final t in data.targets)
    if (isSameDay(t.deadline, day) &&
        (projectId == null
            ? !(data.project(t.projectId)?.archived ?? true)
            : t.projectId == projectId))
      t,
];

/// The week view. Needs a bounded height (put it in an `Expanded` or a
/// `SizedBox`). Arrows, a horizontal swipe and the Today button change the
/// week; tapping a block opens [showSessionSheet].
class WorkSplitView extends ConsumerStatefulWidget {
  /// Only this project's sessions and deadlines when set.
  final String? projectId;

  const WorkSplitView({super.key, this.projectId});

  @override
  ConsumerState<WorkSplitView> createState() => _WorkSplitViewState();
}

class _WorkSplitViewState extends ConsumerState<WorkSplitView> {
  late DateTime _weekStart;
  ScrollController? _scroll;

  @override
  void initState() {
    super.initState();
    _weekStart = startOfIsoWeek(ref.read(todayProvider));
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  void _changeWeek(int delta) =>
      setState(() => _weekStart = addDays(_weekStart, 7 * delta));

  void _goToToday() =>
      setState(() => _weekStart = startOfIsoWeek(ref.read(todayProvider)));

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final dataAsync = ref.watch(projectsDataProvider);
    final data = dataAsync.value;
    final onThisWeek = isSameDay(_weekStart, startOfIsoWeek(today));

    final sessions = data == null
        ? const <Session>[]
        : workSplitSessions(
            data,
            weekStart: _weekStart,
            today: today,
            projectId: widget.projectId,
          );
    // Scroll to the first block of the first week shown (or 08:00).
    _scroll ??= ScrollController(
      initialScrollOffset:
          ((sessions.isEmpty
                  ? workSplitDefaultStartHour
                  : sessions
                            .map((s) => s.startTime.hour)
                            .reduce((a, b) => a < b ? a : b) -
                        1)
              .clamp(0, 23)) *
          workSplitHourHeight,
    );

    final days = [for (var i = 0; i < 7; i++) addDays(_weekStart, i)];

    return GestureDetector(
      key: const ValueKey('work-split-view'),
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() < 200) return;
        _changeWeek(v < 0 ? 1 : -1);
      },
      child: Column(
        children: [
          _WeekToolbar(
            weekStart: _weekStart,
            onPrevious: () => _changeWeek(-1),
            onNext: () => _changeWeek(1),
            onToday: onThisWeek ? null : _goToToday,
          ),
          if (dataAsync.hasError)
            Expanded(
              child: Center(
                child: Text(
                  'The work split could not be loaded.\n'
                  '${dataAsync.error}',
                ),
              ),
            )
          else if (data == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else ...[
            _DayHeaders(
              days: days,
              today: today,
              data: data,
              projectId: widget.projectId,
            ),
            const Divider(height: 1),
            Expanded(
              child: Stack(
                children: [
                  _WeekGrid(
                    controller: _scroll!,
                    days: days,
                    today: today,
                    now: ref.watch(clockProvider)(),
                    sessions: sessions,
                    data: data,
                  ),
                  if (sessions.isEmpty)
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: _EmptyWeekNote(
                          filtered: widget.projectId != null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeekToolbar extends StatelessWidget {
  final DateTime weekStart;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onToday;

  const _WeekToolbar({
    required this.weekStart,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('work-split-prev-week'),
            tooltip: 'Previous week',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              weekLabel(weekStart),
              key: const ValueKey('work-split-week-title'),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('work-split-next-week'),
            tooltip: 'Next week',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          TextButton(
            key: const ValueKey('work-split-today'),
            onPressed: onToday,
            child: const Text('Today'),
          ),
        ],
      ),
    );
  }
}

/// `16 – 22 Nov 2026`, `30 Nov – 6 Dec 2026`, `28 Dec 2026 – 3 Jan 2027`.
String weekLabel(DateTime weekStart) {
  final end = addDays(weekStart, 6);
  if (weekStart.year != end.year) {
    return '${DateFormat('d MMM y').format(weekStart)} – '
        '${DateFormat('d MMM y').format(end)}';
  }
  if (weekStart.month != end.month) {
    return '${DateFormat('d MMM').format(weekStart)} – '
        '${DateFormat('d MMM y').format(end)}';
  }
  return '${weekStart.day} – ${DateFormat('d MMM y').format(end)}';
}

class _DayHeaders extends StatelessWidget {
  final List<DateTime> days;
  final DateTime today;
  final ProjectsData data;
  final String? projectId;

  const _DayHeaders({
    required this.days,
    required this.today,
    required this.data,
    required this.projectId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        const SizedBox(width: _gutterWidth),
        for (final day in days)
          Expanded(
            child: Builder(
              builder: (context) {
                final isToday = isSameDay(day, today);
                final deadlines = deadlinesOn(data, day, projectId: projectId);
                return Padding(
                  key: ValueKey('work-split-day-${dateKey(day)}'),
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    children: [
                      Text(
                        DateFormat('EEE').format(day),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isToday
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isToday ? scheme.primary : null,
                        ),
                        child: Text(
                          '${day.day}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: isToday ? scheme.onPrimary : null,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 18,
                        child: deadlines.isEmpty
                            ? null
                            : _DeadlineMarker(day: day, targets: deadlines),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// A flag per day with deadlines (tooltip: the targets due).
class _DeadlineMarker extends StatelessWidget {
  final DateTime day;
  final List<Target> targets;

  const _DeadlineMarker({required this.day, required this.targets});

  @override
  Widget build(BuildContext context) {
    final label = [
      for (final t in targets) 'Deadline: ${t.title}${t.isDone ? ' ✓' : ''}',
    ].join('\n');
    return Tooltip(
      key: ValueKey('deadline-marker-${dateKey(day)}'),
      message: label,
      triggerMode: TooltipTriggerMode.tap,
      child: Semantics(
        label: label,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.flag_rounded,
              size: 16,
              color: projectColor(targets.first.projectId),
            ),
            if (targets.length > 1)
              Text(
                '${targets.length}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _WeekGrid extends StatelessWidget {
  final ScrollController controller;
  final List<DateTime> days;
  final DateTime today;
  final DateTime now;
  final List<Session> sessions;
  final ProjectsData data;

  const _WeekGrid({
    required this.controller,
    required this.days,
    required this.today,
    required this.now,
    required this.sessions,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const totalHeight = 24 * workSplitHourHeight;
    return SingleChildScrollView(
      key: const ValueKey('work-split-scroll'),
      controller: controller,
      child: SizedBox(
        height: totalHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _gutterWidth,
              child: Stack(
                children: [
                  for (var h = 1; h < 24; h++)
                    Positioned(
                      top: h * workSplitHourHeight - 7,
                      left: 0,
                      right: 6,
                      child: Text(
                        '${h.toString().padLeft(2, '0')}:00',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            for (final day in days)
              Expanded(
                child: _DayColumn(
                  day: day,
                  isToday: isSameDay(day, today),
                  now: now,
                  sessions: [
                    for (final s in sessions)
                      if (isSameDay(s.date, day)) s,
                  ],
                  data: data,
                  canAttend: !day.isAfter(today),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  final DateTime day;
  final bool isToday;
  final DateTime now;
  final List<Session> sessions;
  final ProjectsData data;
  final bool canAttend;

  const _DayColumn({
    required this.day,
    required this.isToday,
    required this.now,
    required this.sessions,
    required this.data,
    required this.canAttend,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lanes = assignLanes(sessions);
    final laneCount = lanes.isEmpty
        ? 1
        : lanes.values.reduce((a, b) => a > b ? a : b) + 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isToday ? scheme.primary.withValues(alpha: 0.05) : null,
        border: Border(
          left: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final laneWidth = constraints.maxWidth / laneCount;
          return Stack(
            children: [
              for (var h = 1; h < 24; h++)
                Positioned(
                  top: h * workSplitHourHeight,
                  left: 0,
                  right: 0,
                  child: Divider(
                    height: 1,
                    thickness: 0.5,
                    color: scheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
              for (final s in sessions)
                Positioned(
                  top: _y(s.startTime.minutesOfDay),
                  height:
                      (_y(s.endTime.minutesOfDay) -
                              _y(s.startTime.minutesOfDay))
                          .clamp(18.0, double.infinity),
                  left: lanes[s.key]! * laneWidth + 1,
                  width: laneWidth - 2,
                  child: SessionBlock(
                    session: s,
                    targetTitle: data.target(s.targetId)?.title ?? 'Target',
                    onTap: () => showSessionSheet(
                      context,
                      session: s,
                      canAttend: canAttend,
                    ),
                  ),
                ),
              if (isToday)
                Positioned(
                  key: const ValueKey('work-split-now-line'),
                  top: _y(now.hour * 60 + now.minute) - 1,
                  left: 0,
                  right: 0,
                  child: Container(height: 2, color: scheme.error),
                ),
            ],
          );
        },
      ),
    );
  }

  static double _y(int minutes) => minutes / 60 * workSplitHourHeight;
}

/// Side-by-side lanes for overlapping sessions of one day (a lane index
/// per `Session.key`). The overlap rule keeps active blocks apart, but
/// past sessions of done targets may still overlap.
Map<String, int> assignLanes(List<Session> daySessions) {
  final sorted = [...daySessions]..sort(compareSessions);
  final laneEnds = <int>[];
  final out = <String, int>{};
  for (final s in sorted) {
    var lane = laneEnds.indexWhere((end) => end <= s.startTime.minutesOfDay);
    if (lane == -1) {
      lane = laneEnds.length;
      laneEnds.add(0);
    }
    laneEnds[lane] = s.endTime.minutesOfDay;
    out[s.key] = lane;
  }
  return out;
}

/// One time block: the project's colour, the target and the times; a ✓
/// when attended. Keyed `session-block-<Session.key>`.
class SessionBlock extends StatelessWidget {
  final Session session;
  final String targetTitle;
  final VoidCallback onTap;

  const SessionBlock({
    super.key,
    required this.session,
    required this.targetTitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = projectColor(session.projectId);
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xFF1E1B2E);
    final times = '${session.startTime}–${session.endTime}';
    return Semantics(
      button: true,
      label:
          '$targetTitle, $times'
          '${session.attended ? ', attended' : ''}',
      excludeSemantics: true,
      child: Material(
        key: ValueKey('session-block-${session.key}'),
        color: session.attended ? color : color.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall / 2),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(3, 2, 2, 2),
            child: LayoutBuilder(
              builder: (context, c) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (session.attended && c.maxWidth > 24)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 11,
                          color: onColor,
                        ),
                      Flexible(
                        child: Text(
                          targetTitle,
                          maxLines: c.maxHeight > 40 ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: onColor,
                            fontSize: 10.5,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (c.maxHeight > 52)
                    Text(
                      times,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: onColor.withValues(alpha: 0.9),
                        fontSize: 9.5,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The sheet for a tapped block: target, project, date and times, a toggle
/// to mark the session attended (today and past only) and a button that
/// opens the target.
Future<void> showSessionSheet(
  BuildContext context, {
  required Session session,
  required bool canAttend,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _SessionSheet(
    actionId: session.actionId,
    date: session.date,
    fallback: session,
    canAttend: canAttend,
  ),
);

class _SessionSheet extends ConsumerWidget {
  final String actionId;
  final DateTime date;
  final Session fallback;
  final bool canAttend;

  const _SessionSheet({
    required this.actionId,
    required this.date,
    required this.fallback,
    required this.canAttend,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final data = ref.watch(projectsDataProvider).value;
    final attended = data?.isAttended(actionId, date) ?? fallback.attended;
    final target = data?.target(fallback.targetId);
    final project = data?.project(fallback.projectId);
    final color = projectColor(fallback.projectId);
    final title = target?.title ?? 'Target';
    return SafeArea(
      child: Padding(
        key: const ValueKey('session-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleLarge),
                      if (project != null)
                        Text(
                          project.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
                if (target != null) TargetStatusChip(status: target.status),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  '${longDate(date)} · '
                  '${fallback.startTime}–${fallback.endTime}',
                  style: theme.textTheme.bodyLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (canAttend)
              Row(
                children: [
                  CheckInButton(
                    key: const ValueKey('session-sheet-attend'),
                    completed: attended,
                    color: color,
                    size: 44,
                    semanticLabel: attended
                        ? 'Unmark attended'
                        : 'Mark attended',
                    onPressed: () => ref
                        .read(projectServiceProvider)
                        .setSessionAttended(actionId, date, !attended),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      attended ? 'Attended — nice work! 🎉' : 'Mark attended',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              )
            else
              Text(
                'You can mark it attended on the day ⏰',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 16),
            if (target != null)
              FilledButton.icon(
                key: const ValueKey('session-sheet-open-target'),
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push(
                    AppRoutes.targetEditor(target.projectId, target.id),
                  );
                },
                icon: const Icon(Icons.flag_rounded),
                label: const Text('Open target'),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyWeekNote extends StatelessWidget {
  final bool filtered;

  const _EmptyWeekNote({required this.filtered});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('work-split-empty'),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        filtered
            ? 'No time blocks this week. Add one to a target ⏰'
            : 'No time blocks this week ⏰',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}
