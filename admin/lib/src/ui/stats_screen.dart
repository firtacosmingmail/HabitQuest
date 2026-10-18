import 'package:flutter/material.dart';

import '../api/admin_api.dart';
import '../api/api_exception.dart';
import '../api/models.dart';
import '../dates.dart';
import 'charts.dart';

/// Date-range presets (rows before the custom range, per the dataviz rules).
enum RangePreset {
  last7('Last 7 days', 7),
  last30('Last 30 days', 30),
  last90('Last 90 days', 90),
  custom('Custom…', 0);

  final String label;
  final int days;
  const RangePreset(this.label, this.days);
}

/// The stats dashboard: one filter row (date range) scoping every tile and
/// chart below it.
class StatsScreen extends StatefulWidget {
  final AdminApi api;
  final DateTime Function() now;

  const StatsScreen({super.key, required this.api, required this.now});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  RangePreset _preset = RangePreset.last30;
  late DateTime _from;
  late DateTime _to;
  AdminStats? _stats;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _applyPreset(RangePreset.last30, load: false);
    _load();
  }

  /// The server counts UTC calendar days.
  DateTime _utcToday() {
    final n = widget.now().toUtc();
    return DateTime(n.year, n.month, n.day);
  }

  void _applyPreset(RangePreset p, {bool load = true}) {
    final today = _utcToday();
    _preset = p;
    _to = today;
    _from = addDays(today, -(p.days - 1));
    if (load) _load();
  }

  Future<void> _pickCustom() async {
    final today = _utcToday();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2026),
      lastDate: today,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: 'Stats range (at most 366 days)',
    );
    if (picked == null) return;
    if (daysBetween(picked.start, picked.end) + 1 > 366) {
      setState(() => _error = 'Pick a range of at most 366 days.');
      return;
    }
    setState(() {
      _preset = RangePreset.custom;
      _from = dateOnly(picked.start);
      _to = dateOnly(picked.end);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.api.stats(from: dateKey(_from), to: dateKey(_to));
      if (!mounted) return;
      setState(() => _stats = s);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = VizTokens.of(context);
    final stats = _stats;
    return Container(
      color: t.page,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Usage stats', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          _filterRow(context),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          if (stats == null && _loading)
            const Center(child: CircularProgressIndicator())
          else if (stats != null)
            // Refetch keeps the frame: the previous render dims while loading.
            AnimatedOpacity(
              opacity: _loading ? 0.5 : 1,
              duration: const Duration(milliseconds: 150),
              child: _Dashboard(stats: stats),
            ),
        ],
      ),
    );
  }

  Widget _filterRow(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final p in RangePreset.values)
          ChoiceChip(
            key: ValueKey('range-${p.name}'),
            label: Text(p.label),
            selected: _preset == p,
            onSelected: (_) => p == RangePreset.custom
                ? _pickCustom()
                : setState(() => _applyPreset(p)),
          ),
        const SizedBox(width: 8),
        Text(
          '${longDate(_from)} – ${longDate(_to)} (UTC days)',
          key: const ValueKey('range-label'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _Dashboard extends StatelessWidget {
  final AdminStats stats;

  const _Dashboard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final days = s.daily.map((d) => parseDateKey(d.date)).toList();
    final dayLabels = days.map(shortDate).toList();
    final dayLong = days.map(longDate).toList();
    final weekLabels = s.weekly
        .map((w) => shortDate(parseDateKey(w.weekStart)))
        .toList();
    final weekLong = s.weekly
        .map(
          (w) =>
              'Week of ${longDate(parseDateKey(w.weekStart))}'
              '${w.days < 7 ? ' (${w.days} days in range)' : ''}',
        )
        .toList();

    final cards = <Widget>[
      ChartCard(
        title: 'Daily active users',
        note:
            'Approximation: users with at least one completed habit that day. '
            'Opening the app without checking anything off is not recorded.',
        kind: ChartKind.line,
        labels: dayLabels,
        longLabels: dayLong,
        values: s.daily.map((d) => d.activeUsers).toList(),
        unit: 'users',
      ),
      ChartCard(
        title: 'Weekly active users',
        note:
            'Distinct users with a completion in each ISO week (Monday start); '
            'edge weeks only count the days inside the range.',
        kind: ChartKind.column,
        labels: weekLabels,
        longLabels: weekLong,
        values: s.weekly.map((w) => w.activeUsers).toList(),
        unit: 'users',
        labelHeader: 'Week',
      ),
      ChartCard(
        title: 'Completions per day',
        note:
            'Completed check-ins by the day they were for (synced accounts only).',
        kind: ChartKind.line,
        labels: dayLabels,
        longLabels: dayLong,
        values: s.daily.map((d) => d.completions).toList(),
        unit: 'completions',
      ),
      ChartCard(
        title: 'New sign-ups per day',
        kind: ChartKind.column,
        labels: dayLabels,
        longLabels: dayLong,
        values: s.daily.map((d) => d.signups).toList(),
        unit: 'sign-ups',
      ),
      ChartCard(
        title: 'New sign-ups per week',
        kind: ChartKind.column,
        labels: weekLabels,
        longLabels: weekLong,
        values: s.weekly.map((w) => w.signups).toList(),
        unit: 'sign-ups',
        labelHeader: 'Week',
      ),
      ChartCard(
        title: 'Habits created per day',
        note:
            'By the habit\'s creation time on the device; includes habits deleted later.',
        kind: ChartKind.column,
        labels: dayLabels,
        longLabels: dayLong,
        values: s.daily.map((d) => d.habitsCreated).toList(),
        unit: 'habits',
      ),
      ChartCard(
        title: 'Quote loves per day',
        note: 'Loves still saved (an unlove removes the record).',
        kind: ChartKind.column,
        labels: dayLabels,
        longLabels: dayLong,
        values: s.daily.map((d) => d.quoteLoves).toList(),
        unit: 'loves',
      ),
      ChartCard(
        title: 'XP distribution',
        note: 'Users with a synced game state, by total XP (all time).',
        kind: ChartKind.column,
        labels: s.xpBuckets.map((b) => b.label).toList(),
        values: s.xpBuckets.map((b) => b.users).toList(),
        unit: 'users',
        labelHeader: 'XP',
      ),
      ChartCard(
        title: 'Best streak distribution',
        note:
            'Best streak ever per user. Current streaks are computed on the '
            'device and not stored on the server.',
        kind: ChartKind.column,
        labels: s.bestStreakBuckets.map((b) => b.label).toList(),
        values: s.bestStreakBuckets.map((b) => b.users).toList(),
        unit: 'users',
        labelHeader: 'Best streak (days)',
      ),
      ChartCard(
        title: 'Highest level reached',
        kind: ChartKind.column,
        labels: s.levels
            .map((b) => b.label.replaceFirst('Level ', 'L'))
            .toList(),
        longLabels: s.levels.map((b) => b.label).toList(),
        values: s.levels.map((b) => b.users).toList(),
        unit: 'users',
        labelHeader: 'Level',
      ),
      _TopQuotes(quotes: s.topQuotes),
      _WidgetUsage(recorded: s.widgetsRecorded, note: s.widgetsNote),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            StatTile(
              label: 'Total users',
              value: s.totals.users,
              caption:
                  '${groupThousands(s.totals.usersWithGameState)} with a synced game state',
              hero: true,
            ),
            StatTile(
              label: 'New sign-ups',
              value: s.range.signups,
              caption: 'in range',
            ),
            StatTile(
              label: 'Avg daily active',
              value: s.range.averageDailyActiveUsers,
              caption: 'users / day',
            ),
            StatTile(
              label: 'Active users',
              value: s.range.activeUsers,
              caption: 'in range',
            ),
            StatTile(
              label: 'Habits created',
              value: s.range.habitsCreated,
              caption: 'in range',
            ),
            StatTile(
              label: 'Completions',
              value: s.range.completions,
              caption: 'in range',
            ),
            StatTile(
              label: 'Quote loves',
              value: s.range.quoteLoves,
              caption: 'in range',
            ),
            StatTile(
              label: 'Habits',
              value: s.totals.activeHabits,
              caption:
                  'active (${groupThousands(s.totals.habits)} incl. archived)',
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, box) {
            final cols = box.maxWidth >= 1100 ? 2 : 1;
            final w = (box.maxWidth - (cols - 1) * 16) / cols;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [for (final c in cards) SizedBox(width: w, child: c)],
            );
          },
        ),
      ],
    );
  }
}

class _TopQuotes extends StatelessWidget {
  final List<TopQuote> quotes;

  const _TopQuotes({required this.quotes});

  @override
  Widget build(BuildContext context) {
    final t = VizTokens.of(context);
    final text = Theme.of(context).textTheme;
    final max = quotes.fold<int>(0, (m, q) => q.loves > m ? q.loves : m);
    return Card(
      color: t.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: t.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Most-loved quotes',
              style: text.titleSmall?.copyWith(
                color: t.inkPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'All time',
              style: text.bodySmall?.copyWith(color: t.inkSecondary),
            ),
            const SizedBox(height: 8),
            if (quotes.isEmpty)
              Text(
                'No loves yet.',
                style: text.bodyMedium?.copyWith(color: t.inkSecondary),
              ),
            for (final q in quotes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '“${q.text}”',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium?.copyWith(
                              color: t.inkPrimary,
                            ),
                          ),
                          Text(
                            [
                              q.author ?? 'Anonymous',
                              if (q.day != null) q.day!,
                            ].join(' · '),
                            style: text.bodySmall?.copyWith(
                              color: t.inkSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // A thin magnitude bar (single series, slot 1).
                          LayoutBuilder(
                            builder: (context, box) => Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                height: 6,
                                width: max == 0
                                    ? 0
                                    : box.maxWidth * q.loves / max,
                                decoration: BoxDecoration(
                                  color: t.series,
                                  borderRadius: const BorderRadius.horizontal(
                                    right: Radius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${groupThousands(q.loves)} ♥',
                      style: text.titleSmall?.copyWith(color: t.inkPrimary),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WidgetUsage extends StatelessWidget {
  final bool recorded;
  final String note;

  const _WidgetUsage({required this.recorded, required this.note});

  @override
  Widget build(BuildContext context) {
    final t = VizTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Card(
      color: t.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: t.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.widgets_outlined, color: t.inkSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Widget usage',
                    style: text.titleSmall?.copyWith(
                      color: t.inkPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    recorded ? 'Recorded' : 'Not recorded',
                    style: text.bodyLarge?.copyWith(color: t.inkPrimary),
                  ),
                  Text(
                    note,
                    style: text.bodySmall?.copyWith(color: t.inkSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
