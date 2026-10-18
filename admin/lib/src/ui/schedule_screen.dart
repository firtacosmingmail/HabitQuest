import 'package:flutter/material.dart';

import '../api/admin_api.dart';
import '../api/api_exception.dart';
import '../api/models.dart';
import '../dates.dart';
import 'quote_editor.dart';

/// One calendar day of the schedule; [quote] null = a gap.
class ScheduleDay {
  final DateTime date;
  final AdminQuote? quote;

  const ScheduleDay(this.date, this.quote);

  bool get isGap => quote == null;
}

/// The [days] days from [from], each with the quote scheduled on it (if any).
List<ScheduleDay> buildSchedule(
  DateTime from,
  int days,
  List<AdminQuote> quotes,
) {
  final byDay = {
    for (final q in quotes)
      if (q.day != null) q.day!: q,
  };
  return [
    for (var i = 0; i < days; i++)
      ScheduleDay(addDays(from, i), byDay[dateKey(addDays(from, i))]),
  ];
}

/// The coming weeks, flagging the days that have no scheduled quote. Those
/// days still get a quote in the app: the `quotes` function falls back to a
/// deterministic pick among the earlier quotes ("cycling").
class ScheduleScreen extends StatefulWidget {
  final AdminApi api;
  final DateTime Function() now;

  const ScheduleScreen({super.key, required this.api, required this.now});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  int _weeks = 8;
  List<ScheduleDay> _days = [];
  bool _loading = false;
  String? _error;

  DateTime get _today => dateOnly(widget.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final from = _today;
    final count = _weeks * 7;
    try {
      final page = await widget.api.listQuotes(
        QuoteQuery(
          from: dateKey(from),
          to: dateKey(addDays(from, count - 1)),
          limit: 500,
        ),
      );
      if (!mounted) return;
      setState(() => _days = buildSchedule(from, count, page.items));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(ScheduleDay d) async {
    final saved = await showQuoteEditor(
      context,
      api: widget.api,
      quote: d.quote,
      initialDay: d.quote == null ? dateKey(d.date) : null,
    );
    if (saved != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final gaps = _days.where((d) => d.isGap).toList();
    // Rows of ISO weeks; the first row starts on today's Monday.
    final rows = <List<ScheduleDay?>>[];
    if (_days.isNotEmpty) {
      final lead = _days.first.date.weekday - DateTime.monday;
      final cells = <ScheduleDay?>[...List.filled(lead, null), ..._days];
      for (var i = 0; i < cells.length; i += 7) {
        final row = cells.sublist(i, (i + 7).clamp(0, cells.length));
        rows.add([...row, ...List.filled(7 - row.length, null)]);
      }
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(child: Text('Coming weeks', style: text.headlineSmall)),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 4, label: Text('4 weeks')),
                ButtonSegment(value: 8, label: Text('8 weeks')),
                ButtonSegment(value: 12, label: Text('12 weeks')),
              ],
              selected: {_weeks},
              onSelectionChanged: (s) {
                setState(() => _weeks = s.first);
                _load();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading && _days.isEmpty) const LinearProgressIndicator(),
        if (_error != null)
          Text(_error!, style: TextStyle(color: scheme.error)),
        if (_days.isNotEmpty)
          Card(
            color: gaps.isEmpty
                ? scheme.secondaryContainer
                : scheme.tertiaryContainer,
            child: ListTile(
              leading: Icon(
                gaps.isEmpty
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
              ),
              title: Text(
                gaps.isEmpty
                    ? 'Every day of the next $_weeks weeks has a quote.'
                    : '${gaps.length} day${gaps.length == 1 ? '' : 's'} without a quote '
                          'in the next $_weeks weeks',
                key: const ValueKey('gap-summary'),
              ),
              subtitle: gaps.isEmpty
                  ? null
                  : Text(
                      'These days fall back to cycling: the app shows a deterministic pick '
                      'among the earlier quotes. First gap: ${longDate(gaps.first.date)}. '
                      'Tap a gap to schedule a quote.',
                    ),
            ),
          ),
        const SizedBox(height: 12),
        if (rows.isNotEmpty)
          Table(
            children: [
              TableRow(
                children: [
                  for (final w in const [
                    'Mon',
                    'Tue',
                    'Wed',
                    'Thu',
                    'Fri',
                    'Sat',
                    'Sun',
                  ])
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(w, style: text.labelMedium),
                    ),
                ],
              ),
              for (final row in rows)
                TableRow(
                  children: [
                    for (final d in row)
                      d == null
                          ? const SizedBox.shrink()
                          : _DayCell(day: d, onTap: () => _open(d)),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final ScheduleDay day;
  final VoidCallback onTap;

  const _DayCell({required this.day, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final q = day.quote;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: q == null
            ? scheme.errorContainer.withValues(alpha: 0.5)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: ValueKey('day-${dateKey(day.date)}'),
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            height: 92,
            padding: const EdgeInsets.all(8),
            decoration: q == null
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.error),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shortDate(day.date),
                  style: text.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                if (q == null)
                  Row(
                    children: [
                      Icon(Icons.autorenew, size: 14, color: scheme.error),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'No quote · cycles',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Expanded(
                    child: Text(
                      q.text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
