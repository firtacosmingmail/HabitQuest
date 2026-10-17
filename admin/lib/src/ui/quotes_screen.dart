import 'dart:async';

import 'package:flutter/material.dart';

import '../api/admin_api.dart';
import '../api/api_exception.dart';
import '../api/models.dart';
import '../dates.dart';
import 'quote_editor.dart';

/// Every quote (past, today, scheduled, unscheduled) with search, a
/// date-range filter, love counts, and create / edit / reschedule /
/// unschedule / delete.
class QuotesScreen extends StatefulWidget {
  final AdminApi api;
  final DateTime Function() now;

  const QuotesScreen({super.key, required this.api, required this.now});

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<QuotesScreen> {
  static const _pageSize = 100;

  final _search = TextEditingController();
  Timer? _debounce;
  DateTimeRange? _range;
  ScheduledFilter _scheduled = ScheduledFilter.all;
  List<AdminQuote> _items = [];
  int _total = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  QuoteQuery _query(int offset) => QuoteQuery(
    query: _search.text,
    from: _range == null ? null : dateKey(_range!.start),
    to: _range == null ? null : dateKey(_range!.end),
    scheduled: _range != null ? ScheduledFilter.all : _scheduled,
    limit: _pageSize,
    offset: offset,
  );

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.listQuotes(
        _query(more ? _items.length : 0),
      );
      if (!mounted) return;
      setState(() {
        _items = more ? [..._items, ...page.items] : page.items;
        _total = page.total;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _pickRange() async {
    final today = dateOnly(widget.now());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(today.year + 3),
      initialDateRange: _range,
      helpText: 'Quotes scheduled between',
    );
    if (picked == null) return;
    setState(() => _range = picked);
    _load();
  }

  void _snack(String message) => ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));

  Future<void> _edit([AdminQuote? q]) async {
    final saved = await showQuoteEditor(context, api: widget.api, quote: q);
    if (saved == null) return;
    _snack(q == null ? 'Quote created' : 'Quote saved');
    _load();
  }

  Future<void> _unschedule(AdminQuote q) async {
    try {
      await widget.api.updateQuote(
        q.id,
        QuoteDraft(text: q.text, author: q.author, day: null),
      );
      _snack('Unscheduled: ${q.day} now falls back to cycling');
      _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _delete(AdminQuote q) async {
    if (!await confirmDelete(context, q)) return;
    try {
      await widget.api.deleteQuote(q.id);
      _snack('Quote deleted');
      _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayKey = dateKey(dateOnly(widget.now()));
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Quotes', style: text.headlineSmall)),
              FilledButton.icon(
                key: const ValueKey('new-quote'),
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('New quote'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // One filter row above the list.
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  key: const ValueKey('quote-search'),
                  controller: _search,
                  onChanged: _onSearch,
                  onSubmitted: (_) => _load(),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search text or author',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('quote-range'),
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range),
                label: Text(
                  _range == null
                      ? 'Any date'
                      : '${shortDate(_range!.start)} – ${shortDate(_range!.end)} ${_range!.end.year}',
                ),
              ),
              if (_range != null)
                IconButton(
                  key: const ValueKey('quote-range-clear'),
                  tooltip: 'Clear the date range',
                  onPressed: () {
                    setState(() => _range = null);
                    _load();
                  },
                  icon: const Icon(Icons.close),
                ),
              if (_range == null)
                SegmentedButton<ScheduledFilter>(
                  segments: const [
                    ButtonSegment(
                      value: ScheduledFilter.all,
                      label: Text('All'),
                    ),
                    ButtonSegment(
                      value: ScheduledFilter.scheduled,
                      label: Text('Scheduled'),
                    ),
                    ButtonSegment(
                      value: ScheduledFilter.unscheduled,
                      label: Text('Unscheduled'),
                    ),
                  ],
                  selected: {_scheduled},
                  onSelectionChanged: (s) {
                    setState(() => _scheduled = s.first);
                    _load();
                  },
                ),
              Text(
                '$_total quote${_total == 1 ? '' : 's'}',
                key: const ValueKey('quote-total'),
                style: text.bodySmall,
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          if (_loading && _items.isEmpty) const LinearProgressIndicator(),
          Expanded(
            child: _items.isEmpty && !_loading
                ? const Center(child: Text('No quotes match.'))
                : ListView.separated(
                    itemCount: _items.length + (_items.length < _total ? 1 : 0),
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      if (i == _items.length) {
                        return Center(
                          child: TextButton(
                            onPressed: _loading
                                ? null
                                : () => _load(more: true),
                            child: Text(
                              'Load more (${_total - _items.length} left)',
                            ),
                          ),
                        );
                      }
                      return _QuoteRow(
                        quote: _items[i],
                        todayKey: todayKey,
                        onEdit: () => _edit(_items[i]),
                        onUnschedule: () => _unschedule(_items[i]),
                        onDelete: () => _delete(_items[i]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _QuoteRow extends StatelessWidget {
  final AdminQuote quote;
  final String todayKey;
  final VoidCallback onEdit;
  final VoidCallback onUnschedule;
  final VoidCallback onDelete;

  const _QuoteRow({
    required this.quote,
    required this.todayKey,
    required this.onEdit,
    required this.onUnschedule,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final q = quote;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final when = q.day == null
        ? 'Unscheduled'
        : q.day == todayKey
        ? 'Today'
        : q.day!.compareTo(todayKey) > 0
        ? 'Upcoming'
        : 'Past';
    return ListTile(
      key: ValueKey('quote-${q.id}'),
      leading: SizedBox(
        width: 110,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              q.day == null ? '—' : longDate(parseDateKey(q.day!)),
              style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              when,
              style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      title: Text(q.text),
      subtitle: Text(q.author ?? 'Anonymous'),
      onTap: onEdit,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message:
                '${q.loves} user${q.loves == 1 ? '' : 's'} love this quote',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('${q.loves}', key: ValueKey('loves-${q.id}')),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Edit or reschedule',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          if (q.day != null)
            IconButton(
              key: ValueKey('unschedule-${q.id}'),
              tooltip: 'Unschedule (keep the quote)',
              onPressed: onUnschedule,
              icon: const Icon(Icons.event_busy_outlined),
            ),
          IconButton(
            key: ValueKey('delete-${q.id}'),
            tooltip: 'Delete',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}
