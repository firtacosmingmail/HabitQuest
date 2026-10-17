/// JSON models of the admin endpoints (see supabase/API.md, section Admin).
library;

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
double _double(Object? v) =>
    v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String? _str(Object? v) => v is String ? v : null;
List<Map<String, dynamic>> _list(Object? v) => v is List
    ? v.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList()
    : const [];
Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const {};

/// A signed-in session (the contract's Session object).
class AdminSession {
  final String accessToken;
  final String refreshToken;

  /// Epoch seconds.
  final int expiresAt;
  final String userId;
  final String? email;

  const AdminSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
    this.email,
  });

  factory AdminSession.fromJson(Map<String, dynamic> j) {
    final user = _map(j['user']);
    return AdminSession(
      accessToken: j['accessToken'] as String,
      refreshToken: j['refreshToken'] as String,
      expiresAt: _int(j['expiresAt']),
      userId: '${user['id']}',
      email: _str(user['email']),
    );
  }
}

/// A quote as the admin sees it: plus its love count.
class AdminQuote {
  final String id;
  final String text;
  final String? author;

  /// `yyyy-MM-dd`, or null when unscheduled.
  final String? day;
  final int loves;
  final String createdAt;
  final String updatedAt;

  const AdminQuote({
    required this.id,
    required this.text,
    this.author,
    this.day,
    this.loves = 0,
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory AdminQuote.fromJson(Map<String, dynamic> j) => AdminQuote(
    id: j['id'] as String,
    text: j['text'] as String,
    author: _str(j['author']),
    day: _str(j['day']),
    loves: _int(j['loves']),
    createdAt: _str(j['createdAt']) ?? '',
    updatedAt: _str(j['updatedAt']) ?? '',
  );

  AdminQuote copyWith({
    String? text,
    String? author,
    String? day,
    bool clearAuthor = false,
    bool clearDay = false,
    int? loves,
  }) => AdminQuote(
    id: id,
    text: text ?? this.text,
    author: clearAuthor ? null : (author ?? this.author),
    day: clearDay ? null : (day ?? this.day),
    loves: loves ?? this.loves,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

enum ScheduledFilter { all, scheduled, unscheduled }

/// GET /admin-quotes query.
class QuoteQuery {
  final String query;
  final String? from;
  final String? to;
  final ScheduledFilter scheduled;
  final int limit;
  final int offset;

  const QuoteQuery({
    this.query = '',
    this.from,
    this.to,
    this.scheduled = ScheduledFilter.all,
    this.limit = 100,
    this.offset = 0,
  });

  Map<String, String> toParams() => {
    if (query.trim().isNotEmpty) 'q': query.trim(),
    'from': ?from,
    'to': ?to,
    if (scheduled != ScheduledFilter.all) 'scheduled': scheduled.name,
    'limit': '$limit',
    if (offset > 0) 'offset': '$offset',
  };
}

class QuotePage {
  final int total;
  final List<AdminQuote> items;

  const QuotePage({required this.total, required this.items});

  factory QuotePage.fromJson(Map<String, dynamic> j) => QuotePage(
    total: _int(j['total']),
    items: _list(j['items']).map(AdminQuote.fromJson).toList(),
  );
}

/// Body of POST /quotes, or the fields of PUT /quotes?id= to change.
class QuoteDraft {
  final String text;
  final String? author;
  final String? day;

  const QuoteDraft({required this.text, this.author, this.day});

  Map<String, dynamic> toJson() => {
    'text': text.trim(),
    'author': (author == null || author!.trim().isEmpty)
        ? null
        : author!.trim(),
    'day': day,
  };
}

// Stats ------------------------------------------------------------------------

class DailyStat {
  final String date;
  final int signups;
  final int activeUsers;
  final int habitsCreated;
  final int completions;
  final int quoteLoves;

  const DailyStat({
    required this.date,
    this.signups = 0,
    this.activeUsers = 0,
    this.habitsCreated = 0,
    this.completions = 0,
    this.quoteLoves = 0,
  });

  factory DailyStat.fromJson(Map<String, dynamic> j) => DailyStat(
    date: '${j['date']}',
    signups: _int(j['signups']),
    activeUsers: _int(j['activeUsers']),
    habitsCreated: _int(j['habitsCreated']),
    completions: _int(j['completions']),
    quoteLoves: _int(j['quoteLoves']),
  );
}

class WeeklyStat {
  final String weekStart;

  /// Days of the week inside the range (< 7 for a partial edge week).
  final int days;
  final int signups;
  final int completions;
  final int activeUsers;

  const WeeklyStat({
    required this.weekStart,
    this.days = 7,
    this.signups = 0,
    this.completions = 0,
    this.activeUsers = 0,
  });

  factory WeeklyStat.fromJson(Map<String, dynamic> j) => WeeklyStat(
    weekStart: '${j['weekStart']}',
    days: _int(j['days']),
    signups: _int(j['signups']),
    completions: _int(j['completions']),
    activeUsers: _int(j['activeUsers']),
  );
}

class StatBucket {
  final String label;
  final int users;

  const StatBucket(this.label, this.users);

  factory StatBucket.fromJson(Map<String, dynamic> j) =>
      StatBucket('${j['label']}', _int(j['users']));
}

class TopQuote {
  final String id;
  final String text;
  final String? author;
  final String? day;
  final int loves;

  const TopQuote({
    required this.id,
    required this.text,
    this.author,
    this.day,
    required this.loves,
  });

  factory TopQuote.fromJson(Map<String, dynamic> j) => TopQuote(
    id: '${j['id']}',
    text: '${j['text']}',
    author: _str(j['author']),
    day: _str(j['day']),
    loves: _int(j['loves']),
  );
}

class StatsTotals {
  final int users;
  final int usersWithGameState;
  final int habits;
  final int activeHabits;
  final int completions;
  final int quotes;
  final int scheduledQuotes;
  final int quoteLoves;

  const StatsTotals({
    this.users = 0,
    this.usersWithGameState = 0,
    this.habits = 0,
    this.activeHabits = 0,
    this.completions = 0,
    this.quotes = 0,
    this.scheduledQuotes = 0,
    this.quoteLoves = 0,
  });

  factory StatsTotals.fromJson(Map<String, dynamic> j) => StatsTotals(
    users: _int(j['users']),
    usersWithGameState: _int(j['usersWithGameState']),
    habits: _int(j['habits']),
    activeHabits: _int(j['activeHabits']),
    completions: _int(j['completions']),
    quotes: _int(j['quotes']),
    scheduledQuotes: _int(j['scheduledQuotes']),
    quoteLoves: _int(j['quoteLoves']),
  );
}

class StatsRange {
  final int signups;
  final int activeUsers;
  final int habitsCreated;
  final int completions;
  final int quoteLoves;
  final double averageDailyActiveUsers;

  const StatsRange({
    this.signups = 0,
    this.activeUsers = 0,
    this.habitsCreated = 0,
    this.completions = 0,
    this.quoteLoves = 0,
    this.averageDailyActiveUsers = 0,
  });

  factory StatsRange.fromJson(Map<String, dynamic> j) => StatsRange(
    signups: _int(j['signups']),
    activeUsers: _int(j['activeUsers']),
    habitsCreated: _int(j['habitsCreated']),
    completions: _int(j['completions']),
    quoteLoves: _int(j['quoteLoves']),
    averageDailyActiveUsers: _double(j['averageDailyActiveUsers']),
  );
}

/// GET /admin-stats.
class AdminStats {
  final String from;
  final String to;
  final StatsTotals totals;
  final StatsRange range;
  final List<DailyStat> daily;
  final List<WeeklyStat> weekly;
  final List<StatBucket> xpBuckets;
  final List<StatBucket> bestStreakBuckets;
  final List<StatBucket> levels;
  final List<TopQuote> topQuotes;
  final bool widgetsRecorded;
  final String widgetsNote;

  const AdminStats({
    required this.from,
    required this.to,
    this.totals = const StatsTotals(),
    this.range = const StatsRange(),
    this.daily = const [],
    this.weekly = const [],
    this.xpBuckets = const [],
    this.bestStreakBuckets = const [],
    this.levels = const [],
    this.topQuotes = const [],
    this.widgetsRecorded = false,
    this.widgetsNote = 'Widget usage is not recorded.',
  });

  factory AdminStats.fromJson(Map<String, dynamic> j) {
    final widgets = _map(j['widgets']);
    return AdminStats(
      from: '${j['from']}',
      to: '${j['to']}',
      totals: StatsTotals.fromJson(_map(j['totals'])),
      range: StatsRange.fromJson(_map(j['range'])),
      daily: _list(j['daily']).map(DailyStat.fromJson).toList(),
      weekly: _list(j['weekly']).map(WeeklyStat.fromJson).toList(),
      xpBuckets: _list(j['xpBuckets']).map(StatBucket.fromJson).toList(),
      bestStreakBuckets: _list(
        j['bestStreakBuckets'],
      ).map(StatBucket.fromJson).toList(),
      levels: _list(j['levels'])
          .map((l) => StatBucket('Level ${_int(l['level'])}', _int(l['users'])))
          .toList(),
      topQuotes: _list(j['topQuotes']).map(TopQuote.fromJson).toList(),
      widgetsRecorded: widgets['recorded'] == true,
      widgetsNote: _str(widgets['note']) ?? 'Widget usage is not recorded.',
    );
  }
}
