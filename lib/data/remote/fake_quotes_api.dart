import 'dart:async';

import '../../core/utils/dates.dart';
import 'api_exception.dart';
import 'quotes_api.dart';

/// In-memory [QuotesApi] following the `quotes` / `quote-loves` contract:
/// the deterministic fallback, history that never includes future days or
/// days without a scheduled quote, and idempotent love / unlove.
///
/// For tests: [offline], [failNextWith], [pause] (holds every call until
/// completed, to observe optimistic updates), [calls].
class FakeQuotesApi implements QuotesApi {
  FakeQuotesApi({
    List<Quote>? quotes,
    DateTime Function()? now,
    Map<String, DateTime>? loves,
  }) : _now = now ?? DateTime.now {
    for (final q in quotes ?? sampleQuotes()) {
      _quotes[q.id] = q.withLoved(false);
    }
    _loves.addAll(loves ?? const {});
  }

  final DateTime Function() _now;
  final _quotes = <String, Quote>{};

  /// Loved quote ids → `lovedAt`.
  final _loves = <String, DateTime>{};

  bool offline = false;

  /// Thrown (once) by the next call, after recording it in [calls].
  ApiException? failNextWith;

  /// When set, every call waits for it to complete (after recording the
  /// call and before answering).
  Completer<void>? pause;

  /// `quoteOfDay <date>`, `pastQuotes <n>`, `quotesBetween <from> <to>`,
  /// `lovedQuotes`, `love <id>`, `unlove <id>`.
  final List<String> calls = [];

  /// The loved quote ids (inspection).
  Set<String> get lovedIds => _loves.keys.toSet();

  /// Adds or replaces a quote.
  void put(Quote quote) => _quotes[quote.id] = quote.withLoved(false);

  /// Five quotes scheduled on the five days ending on [lastDay] (default
  /// 2026-10-20), ids `q1`…`q5` (oldest first).
  static List<Quote> sampleQuotes({DateTime? lastDay}) {
    final last = lastDay ?? DateTime(2026, 10, 20);
    const texts = [
      ('Well done is better than well said.', 'Benjamin Franklin'),
      ('The journey of a thousand miles begins with one step.', 'Lao Tzu'),
      ('Little by little, one travels far.', null),
      ('What you do every day matters more than what you do once.', null),
      ('It always seems impossible until it is done.', 'Nelson Mandela'),
    ];
    return [
      for (var i = 0; i < texts.length; i++)
        Quote(
          id: 'q${i + 1}',
          text: texts[i].$1,
          author: texts[i].$2,
          day: addDays(last, i - texts.length + 1),
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
        ),
    ];
  }

  @override
  Future<DailyQuote> quoteOfDay(DateTime date) async {
    await _enter('quoteOfDay ${dateKey(date)}');
    final day = dateOnly(date);
    if (_quotes.isEmpty) {
      throw const ApiException(
        status: 404,
        code: ApiException.notFound,
        message: 'There are no quotes',
      );
    }
    for (final q in _quotes.values) {
      if (q.day == day) {
        return DailyQuote(date: day, fallback: false, quote: _withLove(q));
      }
    }
    // Deterministic fallback, as on the server.
    final older = _quotes.values
        .where((q) => q.day != null && q.day!.isBefore(day))
        .toList();
    final pool = older.isNotEmpty ? older : _quotes.values.toList();
    pool.sort(_byDayThenId);
    final index = daysBetween(DateTime(1970), day) % pool.length;
    return DailyQuote(date: day, fallback: true, quote: _withLove(pool[index]));
  }

  @override
  Future<QuoteHistory> pastQuotes(int days) async {
    await _enter('pastQuotes $days');
    if (days < 1 || days > 366) throw _invalid('past must be 1 to 366');
    final today = _serverToday();
    return _history(addDays(today, -days), addDays(today, -1));
  }

  @override
  Future<QuoteHistory> quotesBetween(DateTime from, DateTime to) async {
    await _enter('quotesBetween ${dateKey(from)} ${dateKey(to)}');
    final f = dateOnly(from);
    final t = dateOnly(to);
    if (t.isBefore(f) || daysBetween(f, t) >= 366) {
      throw _invalid('from/to must be ordered and at most 366 days apart');
    }
    final today = _serverToday();
    return _history(f, t.isAfter(today) ? today : t);
  }

  @override
  Future<List<Quote>> lovedQuotes() async {
    await _enter('lovedQuotes');
    final ids = _loves.keys.where(_quotes.containsKey).toList()
      ..sort((a, b) => _loves[b]!.compareTo(_loves[a]!));
    return [for (final id in ids) _withLove(_quotes[id]!)];
  }

  @override
  Future<Quote> love(String quoteId) async {
    await _enter('love $quoteId');
    final quote = _quotes[quoteId];
    if (quote == null) {
      throw const ApiException(
        status: 404,
        code: ApiException.notFound,
        message: 'Quote not found',
      );
    }
    _loves.putIfAbsent(quoteId, () => _now().toUtc());
    return _withLove(quote);
  }

  @override
  Future<void> unlove(String quoteId) async {
    await _enter('unlove $quoteId');
    _loves.remove(quoteId);
  }

  QuoteHistory _history(DateTime from, DateTime to) {
    final items =
        _quotes.values
            .where(
              (q) =>
                  q.day != null &&
                  !q.day!.isBefore(from) &&
                  !q.day!.isAfter(to),
            )
            .map(_withLove)
            .toList()
          ..sort((a, b) => b.day!.compareTo(a.day!));
    return QuoteHistory(from: from, to: to, items: items);
  }

  /// The server's today (UTC calendar day), as a local-midnight date.
  DateTime _serverToday() {
    final u = _now().toUtc();
    return DateTime(u.year, u.month, u.day);
  }

  Quote _withLove(Quote q) {
    final at = _loves[q.id];
    return at == null ? q.withLoved(false) : q.withLoved(true, lovedAt: at);
  }

  static int _byDayThenId(Quote a, Quote b) {
    if (a.day != b.day) {
      if (a.day == null) return 1;
      if (b.day == null) return -1;
      return a.day!.compareTo(b.day!);
    }
    return a.id.compareTo(b.id);
  }

  static ApiException _invalid(String message) => ApiException(
    status: 400,
    code: ApiException.invalidInput,
    message: message,
  );

  Future<void> _enter(String call) async {
    calls.add(call);
    final gate = pause;
    if (gate != null) await gate.future;
    if (offline) {
      throw const ApiException(
        code: ApiException.networkError,
        message: 'Offline (fake)',
      );
    }
    final fail = failNextWith;
    if (fail != null) {
      failNextWith = null;
      throw fail;
    }
  }
}
