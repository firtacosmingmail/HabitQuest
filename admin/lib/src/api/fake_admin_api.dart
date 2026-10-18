import 'dart:math' as math;

import '../dates.dart';
import 'admin_api.dart';
import 'api_exception.dart';
import 'models.dart';

/// In-memory [AdminApi] mirroring the server semantics (admin check, search,
/// ordering, day_taken, delete). Used by the widget tests and by the demo
/// mode (`--dart-define=ADMIN_DEMO=true`), which needs no backend.
class FakeAdminApi implements AdminApi {
  /// email (lower-case) → password.
  final Map<String, String> passwords;

  /// Lower-cased admin emails (the server's QUOTE_ADMINS).
  final Set<String> admins;
  final List<AdminQuote> quotes;
  final AdminStats Function(String from, String to) statsBuilder;

  /// Delay on every call, to exercise loading states.
  final Duration latency;

  String? _email;
  int _seq = 0;

  /// Every query sent to [listQuotes] / [stats], for assertions.
  final List<QuoteQuery> quoteQueries = [];
  final List<(String, String)> statsCalls = [];

  FakeAdminApi({
    Map<String, String>? passwords,
    Set<String>? admins,
    List<AdminQuote>? quotes,
    AdminStats Function(String from, String to)? statsBuilder,
    this.latency = Duration.zero,
  }) : passwords = passwords ?? {},
       admins = admins ?? {},
       quotes = quotes ?? [],
       statsBuilder = statsBuilder ?? demoStats;

  /// Demo data: any email with password `demo`; admin@example.com and
  /// firtacosmin@gmail.com are admins, everyone else sees "Not authorised".
  factory FakeAdminApi.demo({DateTime? today}) {
    final t = dateOnly(today ?? DateTime.now());
    const texts = [
      ('Well done is better than well said.', 'Benjamin Franklin'),
      ('Fall seven times, stand up eight.', null),
      ('Nothing will work unless you do.', 'Maya Angelou'),
      (
        'Small deeds done are better than great deeds planned.',
        'Peter Marshall',
      ),
      ('The secret of getting ahead is getting started.', null),
      ('It always seems impossible until it is done.', 'Nelson Mandela'),
      ('Little by little, one travels far.', 'J. R. R. Tolkien'),
      ('Act as if what you do makes a difference. It does.', 'William James'),
    ];
    final quotes = <AdminQuote>[];
    var n = 0;
    for (var d = -10; d <= 30; d++) {
      if (d > 3 && d % 6 == 0) continue; // a few gaps in the coming weeks
      final (text, author) = texts[n % texts.length];
      n++;
      quotes.add(
        AdminQuote(
          id: _uuid(n),
          text: n <= texts.length ? text : '$text (#$n)',
          author: author,
          day: dateKey(addDays(t, d)),
          loves: d <= 0 ? (n * 7) % 13 : 0,
        ),
      );
    }
    quotes.add(AdminQuote(id: _uuid(++n), text: 'Keep going.'));
    return _DemoApi(quotes: quotes);
  }

  static String _uuid(int n) =>
      '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

  Future<void> _wait() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  void _requireAdmin() {
    final email = _email;
    if (email == null) {
      throw const ApiException(
        status: 401,
        code: ApiException.unauthorized,
        message: 'Not signed in',
      );
    }
    if (!admins.contains(email)) {
      throw const ApiException(
        status: 403,
        code: ApiException.forbidden,
        message: 'Admins only',
      );
    }
  }

  bool _passwordOk(String email, String password) =>
      passwords[email] == password;

  @override
  Future<AdminSession> signIn(String email, String password) async {
    await _wait();
    final e = email.trim().toLowerCase();
    if (!_passwordOk(e, password)) {
      throw const ApiException(
        status: 401,
        code: ApiException.invalidCredentials,
        message: 'Invalid email or password',
      );
    }
    _email = e;
    return AdminSession(
      accessToken: 'fake-token',
      refreshToken: 'fake-refresh',
      expiresAt: 0,
      userId: 'user-$e',
      email: e,
    );
  }

  @override
  Future<void> checkAdmin() async {
    await _wait();
    _requireAdmin();
  }

  @override
  Future<void> signOut() async {
    _email = null;
  }

  static int _order(AdminQuote a, AdminQuote b) {
    if (a.day != b.day) {
      if (a.day == null) return -1;
      if (b.day == null) return 1;
      return b.day!.compareTo(a.day!);
    }
    return b.createdAt.compareTo(a.createdAt);
  }

  @override
  Future<QuotePage> listQuotes(QuoteQuery q) async {
    await _wait();
    _requireAdmin();
    quoteQueries.add(q);
    final needle = q.query.trim().toLowerCase();
    final hits = quotes.where((x) {
      if (needle.isNotEmpty &&
          !x.text.toLowerCase().contains(needle) &&
          !(x.author ?? '').toLowerCase().contains(needle)) {
        return false;
      }
      if (q.from != null && (x.day == null || x.day!.compareTo(q.from!) < 0)) {
        return false;
      }
      if (q.to != null && (x.day == null || x.day!.compareTo(q.to!) > 0)) {
        return false;
      }
      if (q.scheduled == ScheduledFilter.scheduled && x.day == null) {
        return false;
      }
      if (q.scheduled == ScheduledFilter.unscheduled && x.day != null) {
        return false;
      }
      return true;
    }).toList()..sort(_order);
    return QuotePage(
      total: hits.length,
      items: hits.skip(q.offset).take(q.limit).toList(),
    );
  }

  void _checkDay(String? day, [String? self]) {
    if (day == null) return;
    if (quotes.any((q) => q.day == day && q.id != self)) {
      throw ApiException(
        status: 409,
        code: ApiException.dayTaken,
        message: 'Another quote is already scheduled on $day',
      );
    }
  }

  @override
  Future<AdminQuote> createQuote(QuoteDraft draft) async {
    await _wait();
    _requireAdmin();
    final j = draft.toJson();
    _checkDay(j['day'] as String?);
    final q = AdminQuote(
      id: _uuid(1000 + ++_seq),
      text: j['text'] as String,
      author: j['author'] as String?,
      day: j['day'] as String?,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    quotes.add(q);
    return q;
  }

  @override
  Future<AdminQuote> updateQuote(String id, QuoteDraft draft) async {
    await _wait();
    _requireAdmin();
    final i = quotes.indexWhere((q) => q.id == id);
    if (i < 0) {
      throw const ApiException(
        status: 404,
        code: ApiException.notFound,
        message: 'No such quote',
      );
    }
    final j = draft.toJson();
    _checkDay(j['day'] as String?, id);
    final old = quotes[i];
    final next = AdminQuote(
      id: id,
      text: j['text'] as String,
      author: j['author'] as String?,
      day: j['day'] as String?,
      loves: old.loves,
      createdAt: old.createdAt,
    );
    quotes[i] = next;
    return next;
  }

  @override
  Future<void> deleteQuote(String id) async {
    await _wait();
    _requireAdmin();
    final before = quotes.length;
    quotes.removeWhere((q) => q.id == id);
    if (quotes.length == before) {
      throw const ApiException(
        status: 404,
        code: ApiException.notFound,
        message: 'No such quote',
      );
    }
  }

  @override
  Future<AdminStats> stats({required String from, required String to}) async {
    await _wait();
    _requireAdmin();
    statsCalls.add((from, to));
    return statsBuilder(from, to);
  }

  /// Deterministic synthetic stats for [from]..[to] (aggregates only).
  static AdminStats demoStats(String from, String to) {
    final start = parseDateKey(from);
    final days = daysBetween(start, parseDateKey(to)) + 1;
    final daily = <DailyStat>[];
    for (var i = 0; i < days; i++) {
      final d = addDays(start, i);
      final seed = d.millisecondsSinceEpoch ~/ 86400000;
      final wave = (math.sin(seed / 3) + 1) / 2;
      final weekend = d.weekday >= 6 ? 0.8 : 1.0;
      final dau = (24 + 10 * wave + seed % 5) * weekend;
      daily.add(
        DailyStat(
          date: dateKey(d),
          signups: (seed * 7) % 4,
          activeUsers: dau.round(),
          habitsCreated: (seed * 3) % 5,
          completions: (dau * 3.2).round(),
          quoteLoves: (seed * 5) % 6,
        ),
      );
    }
    final weeks = <String, List<DailyStat>>{};
    for (final d in daily) {
      weeks
          .putIfAbsent(dateKey(startOfIsoWeek(parseDateKey(d.date))), () => [])
          .add(d);
    }
    int sum(Iterable<int> xs) => xs.fold(0, (a, b) => a + b);
    return AdminStats(
      from: from,
      to: to,
      totals: const StatsTotals(
        users: 1284,
        usersWithGameState: 1102,
        habits: 4310,
        activeHabits: 3720,
        completions: 98120,
        quotes: 90,
        scheduledQuotes: 88,
        quoteLoves: 2304,
      ),
      range: StatsRange(
        signups: sum(daily.map((d) => d.signups)),
        activeUsers: (sum(daily.map((d) => d.activeUsers)) / 2.2).round(),
        habitsCreated: sum(daily.map((d) => d.habitsCreated)),
        completions: sum(daily.map((d) => d.completions)),
        quoteLoves: sum(daily.map((d) => d.quoteLoves)),
        averageDailyActiveUsers: days == 0
            ? 0
            : (sum(daily.map((d) => d.activeUsers)) / days * 10).round() / 10,
      ),
      daily: daily,
      weekly: [
        for (final e in weeks.entries)
          WeeklyStat(
            weekStart: e.key,
            days: e.value.length,
            signups: sum(e.value.map((d) => d.signups)),
            completions: sum(e.value.map((d) => d.completions)),
            activeUsers: (sum(e.value.map((d) => d.activeUsers)) / 2.5).round(),
          ),
      ],
      xpBuckets: const [
        StatBucket('0', 182),
        StatBucket('1–99', 240),
        StatBucket('100–499', 310),
        StatBucket('500–999', 170),
        StatBucket('1000–2499', 120),
        StatBucket('2500–4999', 52),
        StatBucket('5000–9999', 21),
        StatBucket('10000+', 7),
      ],
      bestStreakBuckets: const [
        StatBucket('0', 150),
        StatBucket('1–2', 280),
        StatBucket('3–6', 330),
        StatBucket('7–13', 190),
        StatBucket('14–29', 92),
        StatBucket('30–59', 41),
        StatBucket('60–99', 14),
        StatBucket('100+', 5),
      ],
      levels: const [
        StatBucket('Level 1', 420),
        StatBucket('Level 2', 300),
        StatBucket('Level 3', 190),
        StatBucket('Level 4', 110),
        StatBucket('Level 5', 82),
      ],
      topQuotes: const [
        TopQuote(
          id: 'q1',
          text: 'Fall seven times, stand up eight.',
          loves: 64,
        ),
        TopQuote(
          id: 'q2',
          text: 'Well done is better than well said.',
          author: 'Benjamin Franklin',
          loves: 51,
        ),
        TopQuote(
          id: 'q3',
          text: 'Little by little, one travels far.',
          author: 'J. R. R. Tolkien',
          loves: 38,
        ),
      ],
    );
  }
}

/// Demo mode: any email signs in with the password `demo`.
class _DemoApi extends FakeAdminApi {
  _DemoApi({required super.quotes})
    : super(
        admins: {'admin@example.com', 'firtacosmin@gmail.com'},
        latency: const Duration(milliseconds: 250),
      );

  @override
  bool _passwordOk(String email, String password) =>
      email.contains('@') && password == 'demo';
}
