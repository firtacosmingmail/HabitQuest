/// The work split: a Monday-first week view with hour rows and a time block
/// per time block session, coloured per project and labelled with the
/// block label (else the project name). Used by the Calendar tab (all projects) and by the project
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
import '../models/goal.dart';
import '../projects_providers.dart';
import 'widgets/project_widgets.dart';
import '../../habits/widgets/check_in_button.dart';

/// First hour shown by default (the range never starts later than this).
const workSplitDefaultStartHour = 6;

/// Hour the default range ends at (it never ends earlier than this).
const workSplitDefaultEndHour = 20;

/// Hours revealed by one tap on an expand button.
const workSplitExpandStep = 2;

/// Smallest hour-row height (logical pixels). The automatic range's rows
/// share the frame's height; only when it cannot fit at this size does the
/// grid get taller than the frame. 06:00–20:00 fits even on a 320×568
/// phone (~13 px rows).
const workSplitMinHourHeight = 12.0;

/// Below this row height only every second hour is labelled.
const _denseHourHeight = 16.0;

/// How long range / row-height changes animate.
const workSplitAnimationDuration = Duration(milliseconds: 300);

/// Height of each expand strip (above and below the grid).
const _stripHeight = 30.0;

/// Width of the hour labels column.
const _gutterWidth = 40.0;

/// The visible hours of the grid: from [start] (inclusive) to [end]
/// (exclusive), whole hours in 0..24.
typedef HourRange = ({int start, int end});

/// The range a week needs: 06:00–20:00, extended to the floor of the
/// earliest session start and the ceiling of the latest session end.
HourRange workSplitAutoRange(Iterable<Session> sessions) {
  var start = workSplitDefaultStartHour;
  var end = workSplitDefaultEndHour;
  for (final s in sessions) {
    final from = s.startTime.minutesOfDay ~/ 60;
    final to = (s.endTime.minutesOfDay + 59) ~/ 60;
    if (from < start) start = from;
    if (to > end) end = to;
  }
  return (start: start, end: end.clamp(0, 24));
}

/// The visible range: the week's [workSplitAutoRange] widened by the
/// manual expansion ([earlier] / [later] extra hours), within 00–24.
HourRange workSplitVisibleRange(
  Iterable<Session> sessions, {
  int earlier = 0,
  int later = 0,
}) {
  final auto = workSplitAutoRange(sessions);
  return (
    start: (auto.start - earlier).clamp(0, 24),
    end: (auto.end + later).clamp(0, 24),
  );
}

/// The sessions shown in the week starting [weekStart] (Monday): every
/// session of the week, except sessions of archived projects (unless
/// [projectId] is given).
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
              : s.projectId == projectId))
        s,
  ];
}

/// The goals whose deadline falls on [day] (same filter as the blocks).
List<Goal> deadlinesOn(
  ProjectsData data,
  DateTime day, {
  String? projectId,
}) => [
  for (final t in data.goals)
    if (isSameDay(t.deadline, day) &&
        (projectId == null
            ? !(data.project(t.projectId)?.archived ?? true)
            : t.projectId == projectId))
      t,
];

/// The week view. Arrows, a horizontal swipe and the Today button change
/// the week; tapping a block opens [showSessionSheet].
///
/// Range: [workSplitVisibleRange] of the week's sessions. The hour-row
/// height is fitted to the AUTOMATIC range ([workSplitAutoRange]): its
/// hours share the grid's fitted height. The buttons above and below the
/// grid reveal [workSplitExpandStep] earlier / later hours at that same row
/// height, so the grid grows taller (animated) instead of squeezing the
/// rows; "Reset" shrinks it back. The manual expansion is kept across
/// rebuilds (data changes) and reset when the week changes.
///
/// Two layouts:
/// * [gridHeight] null (Calendar tab): needs a bounded height (an
///   `Expanded`); the grid fits the space left under the headers, and the
///   body (expand strips + grid) scrolls vertically as a whole once an
///   expansion makes it taller. The grid has no scroll of its own.
/// * [gridHeight] set (project details card): the view sizes itself; the
///   automatic range fits [gridHeight] and an expansion makes the view (and
///   the card around it) taller. The screen around it scrolls.
class WorkSplitView extends ConsumerStatefulWidget {
  /// Only this project's sessions and deadlines when set.
  final String? projectId;

  /// The grid's fitted height when the view sizes itself (see above).
  final double? gridHeight;

  const WorkSplitView({super.key, this.projectId, this.gridHeight});

  @override
  ConsumerState<WorkSplitView> createState() => _WorkSplitViewState();
}

class _WorkSplitViewState extends ConsumerState<WorkSplitView> {
  late DateTime _weekStart;

  /// Manual expansion, in extra hours before / after the automatic range.
  int _earlier = 0;
  int _later = 0;

  /// Set by "Later": once the grid has grown, scroll the new hours in.
  bool _revealLater = false;
  final _bottomStripKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _weekStart = startOfIsoWeek(ref.read(todayProvider));
  }

  void _setWeek(DateTime weekStart) => setState(() {
    if (!isSameDay(weekStart, _weekStart)) {
      _earlier = 0;
      _later = 0;
      _revealLater = false;
    }
    _weekStart = weekStart;
  });

  void _changeWeek(int delta) => _setWeek(addDays(_weekStart, 7 * delta));

  void _goToToday() => _setWeek(startOfIsoWeek(ref.read(todayProvider)));

  void _expandLater() => setState(() {
    _later += workSplitExpandStep;
    _revealLater = true;
  });

  void _reset() => setState(() {
    _earlier = 0;
    _later = 0;
    _revealLater = false;
  });

  /// After a "Later" expansion has animated: bring the new bottom hours
  /// into view (the Calendar body or the details screen scrolls).
  void _onGridAnimationEnd() {
    if (!_revealLater) return;
    _revealLater = false;
    final ctx = _bottomStripKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: workSplitAnimationDuration,
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

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
    final range = workSplitVisibleRange(
      sessions,
      earlier: _earlier,
      later: _later,
    );
    final expanded = _earlier > 0 || _later > 0;

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
        mainAxisSize: widget.gridHeight == null
            ? MainAxisSize.max
            : MainAxisSize.min,
        children: [
          _WeekToolbar(
            weekStart: _weekStart,
            onPrevious: () => _changeWeek(-1),
            onNext: () => _changeWeek(1),
            onToday: onThisWeek ? null : _goToToday,
          ),
          if (dataAsync.hasError)
            _placeholder(
              Center(
                child: Text(
                  'The work split could not be loaded.\n'
                  '${dataAsync.error}',
                ),
              ),
            )
          else if (data == null)
            _placeholder(const Center(child: CircularProgressIndicator()))
          else ...[
            _DayHeaders(
              days: days,
              today: today,
              data: data,
              projectId: widget.projectId,
            ),
            const Divider(height: 1),
            _body(
              range: range,
              auto: workSplitAutoRange(sessions),
              expanded: expanded,
              days: days,
              today: today,
              sessions: sessions,
              data: data,
            ),
          ],
        ],
      ),
    );
  }

  /// Loading / error content: fills the frame, or the fitted grid height.
  Widget _placeholder(Widget child) {
    final h = widget.gridHeight;
    return h == null
        ? Expanded(child: child)
        : SizedBox(height: h + 2 * _stripHeight, child: child);
  }

  /// The expand strips and the grid. Rows: the fitted height over the
  /// automatic range's hours (at least [workSplitMinHourHeight]); the grid
  /// is that row height times the visible hours.
  Widget _body({
    required HourRange range,
    required HourRange auto,
    required bool expanded,
    required List<DateTime> days,
    required DateTime today,
    required List<Session> sessions,
    required ProjectsData data,
  }) {
    Widget content(double fitted) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ExpandStrip(
          key: const ValueKey('work-split-expand-top'),
          icon: Icons.keyboard_arrow_up_rounded,
          label: 'Earlier',
          buttonKey: const ValueKey('work-split-expand-earlier'),
          onExpand: range.start > 0
              ? () => setState(() => _earlier += workSplitExpandStep)
              : null,
          onCollapse: expanded ? _reset : null,
        ),
        _WeekGrid(
          range: range,
          autoHours: auto.end - auto.start,
          fittedHeight: fitted,
          days: days,
          today: today,
          now: ref.watch(clockProvider)(),
          sessions: sessions,
          data: data,
          onAnimationEnd: _onGridAnimationEnd,
          overlay: sessions.isEmpty
              ? Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _EmptyWeekNote(filtered: widget.projectId != null),
                  ),
                )
              : null,
        ),
        _ExpandStrip(
          key: _bottomStripKey,
          icon: Icons.keyboard_arrow_down_rounded,
          label: 'Later',
          buttonKey: const ValueKey('work-split-expand-later'),
          onExpand: range.end < 24 ? _expandLater : null,
        ),
      ],
    );

    final gridHeight = widget.gridHeight;
    if (gridHeight != null) return content(gridHeight);
    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          key: const ValueKey('work-split-body-scroll'),
          child: content(
            (constraints.maxHeight - 2 * _stripHeight).clamp(
              0.0,
              double.infinity,
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin bar above / below the grid with an expand button (and, on the
/// top bar, "Reset" while the range is manually expanded).
class _ExpandStrip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Key buttonKey;
  final VoidCallback? onExpand;
  final VoidCallback? onCollapse;

  const _ExpandStrip({
    super.key,
    required this.icon,
    required this.label,
    required this.buttonKey,
    required this.onExpand,
    this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      minimumSize: const Size(0, 30),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      textStyle: Theme.of(context).textTheme.labelMedium,
    );
    return SizedBox(
      height: _stripHeight,
      child: Row(
        children: [
          const SizedBox(width: _gutterWidth),
          Expanded(
            child: Center(
              child: TextButton.icon(
                key: buttonKey,
                style: style,
                onPressed: onExpand,
                icon: Icon(icon, size: 18),
                label: Text(label),
              ),
            ),
          ),
          SizedBox(
            width: 72,
            child: onCollapse == null
                ? null
                : TextButton(
                    key: const ValueKey('work-split-collapse'),
                    style: style,
                    onPressed: onCollapse,
                    child: const Text('Reset'),
                  ),
          ),
        ],
      ),
    );
  }
}

/// An hour range with fractional ends, for the animation.
@immutable
class _Span {
  final double start;
  final double end;

  /// Hours of the automatic range (the rows' fitted height divides by it).
  final double base;

  const _Span(this.start, this.end, this.base);

  double get hours => end - start;

  @override
  bool operator ==(Object other) =>
      other is _Span &&
      other.start == start &&
      other.end == end &&
      other.base == base;

  @override
  int get hashCode => Object.hash(start, end, base);
}

class _SpanTween extends Tween<_Span> {
  _SpanTween({super.end});

  @override
  _Span lerp(double t) => _Span(
    begin!.start + (end!.start - begin!.start) * t,
    begin!.end + (end!.end - begin!.end) * t,
    begin!.base + (end!.base - begin!.base) * t,
  );
}

/// Where the (animated) visible range puts things: y of a time of day.
class _Geometry {
  final _Span span;
  final double hourHeight;

  const _Geometry(this.span, this.hourHeight);

  double y(int minutes) => (minutes / 60 - span.start) * hourHeight;

  /// The whole hours on or inside the range.
  Iterable<int> get hours sync* {
    for (var h = span.start.ceil(); h <= span.end.floor(); h++) {
      yield h;
    }
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
                            : _DeadlineMarker(day: day, goals: deadlines),
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

/// A flag per day with deadlines (tooltip: the goals due).
class _DeadlineMarker extends StatelessWidget {
  final DateTime day;
  final List<Goal> goals;

  const _DeadlineMarker({required this.day, required this.goals});

  @override
  Widget build(BuildContext context) {
    final label = [
      for (final t in goals) 'Deadline: ${t.title}${t.isDone ? ' ✓' : ''}',
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
              color: projectColor(goals.first.projectId),
            ),
            if (goals.length > 1)
              Text(
                '${goals.length}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
      ),
    );
  }
}

/// The hour grid: rows of [fittedHeight] / [autoHours] (at least
/// [workSplitMinHourHeight]), [range] hours tall. Range and height changes
/// animate. No scroll of its own.
class _WeekGrid extends StatelessWidget {
  final HourRange range;
  final int autoHours;
  final double fittedHeight;
  final List<DateTime> days;
  final DateTime today;
  final DateTime now;
  final List<Session> sessions;
  final ProjectsData data;
  final VoidCallback onAnimationEnd;
  final Widget? overlay;

  const _WeekGrid({
    required this.range,
    required this.autoHours,
    required this.fittedHeight,
    required this.days,
    required this.today,
    required this.now,
    required this.sessions,
    required this.data,
    required this.onAnimationEnd,
    this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<_Span>(
      tween: _SpanTween(
        end: _Span(
          range.start.toDouble(),
          range.end.toDouble(),
          autoHours.toDouble(),
        ),
      ),
      duration: workSplitAnimationDuration,
      curve: Curves.easeInOutCubic,
      onEnd: onAnimationEnd,
      builder: (context, span, _) {
        final base = span.base <= 0 ? 1.0 : span.base;
        final fitted = fittedHeight / base;
        final hourHeight = fitted < workSplitMinHourHeight
            ? workSplitMinHourHeight
            : fitted;
        final height = hourHeight * (span.hours <= 0 ? 0 : span.hours);
        return SizedBox(
          key: const ValueKey('work-split-grid'),
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: _grid(context, _Geometry(span, hourHeight), height),
              ),
              ?overlay,
            ],
          ),
        );
      },
    );
  }

  Widget _grid(BuildContext context, _Geometry g, double height) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _gutterWidth,
          child: Stack(
            children: [
              for (final h in g.hours)
                if (g.hourHeight >= _denseHourHeight || h.isEven)
                  Positioned(
                    key: ValueKey('work-split-hour-$h'),
                    top: (g.y(h * 60) - 7).clamp(0.0, height - 14),
                    left: 0,
                    right: 6,
                    child: Text(
                      '${h.toString().padLeft(2, '0')}:00',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        height: 1.3,
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
              geometry: g,
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
    );
  }
}

class _DayColumn extends StatelessWidget {
  final _Geometry geometry;
  final DateTime day;
  final bool isToday;
  final DateTime now;
  final List<Session> sessions;
  final ProjectsData data;
  final bool canAttend;

  const _DayColumn({
    required this.geometry,
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
              for (final h in geometry.hours)
                Positioned(
                  top: _y(h * 60),
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
                    title:
                        s.label ?? data.project(s.projectId)?.name ?? 'Project',
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

  double _y(int minutes) => geometry.y(minutes);
}

/// Side-by-side lanes for overlapping sessions of one day (a lane index
/// per `Session.key`). The overlap rule keeps active blocks apart, but
/// merged data from two devices may still overlap.
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

/// One time block: the project's colour, the block label (or project name) and the times; a ✓
/// when attended. Keyed `session-block-<Session.key>`.
class SessionBlock extends StatelessWidget {
  final Session session;
  final String title;
  final VoidCallback onTap;

  const SessionBlock({
    super.key,
    required this.session,
    required this.title,
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
          '$title, $times'
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
                          title,
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

/// The sheet for a tapped block: label, project, date and times, a toggle
/// to mark the session attended (today and past only) and a button that
/// opens the project.
Future<void> showSessionSheet(
  BuildContext context, {
  required Session session,
  required bool canAttend,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _SessionSheet(
    timeBlockId: session.timeBlockId,
    date: session.date,
    fallback: session,
    canAttend: canAttend,
  ),
);

class _SessionSheet extends ConsumerWidget {
  final String timeBlockId;
  final DateTime date;
  final Session fallback;
  final bool canAttend;

  const _SessionSheet({
    required this.timeBlockId,
    required this.date,
    required this.fallback,
    required this.canAttend,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final data = ref.watch(projectsDataProvider).value;
    final attended =
        data?.isAttended(timeBlockId, date) ?? fallback.attended;
    final project = data?.project(fallback.projectId);
    final color = projectColor(fallback.projectId);
    final title = fallback.label ?? project?.name ?? 'Project';
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
                        .setSessionAttended(timeBlockId, date, !attended),
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
            if (project != null)
              FilledButton.icon(
                key: const ValueKey('session-sheet-open-project'),
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push(AppRoutes.projectDetails(project.id));
                },
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Open project'),
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
            ? 'No time blocks this week. Add one to a project ⏰'
            : 'No time blocks this week ⏰',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}
