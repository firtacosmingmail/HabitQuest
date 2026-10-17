import '../../core/utils/dates.dart';
import '../remote/json_utils.dart';

/// A quote from the `quotes` / `quote-loves` Edge Functions (see the
/// "Quotes" section of `supabase/API.md`).
///
/// Plain data, JSON in the contract's shape, so other features (e.g. the
/// home-screen widget bridge) can read [text] and [author] directly.
class Quote {
  final String id;
  final String text;

  /// `null` for anonymous quotes and proverbs.
  final String? author;

  /// The calendar day the quote is scheduled for (local midnight of that
  /// `yyyy-MM-dd`), or `null` when it is not scheduled.
  final DateTime? day;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Whether the signed-in user has loved (saved) this quote.
  final bool loved;

  /// When the user loved it (only in `quote-loves` responses).
  final DateTime? lovedAt;

  const Quote({
    required this.id,
    required this.text,
    this.author,
    this.day,
    this.createdAt,
    this.updatedAt,
    this.loved = false,
    this.lovedAt,
  });

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
    id: readString(json, 'id'),
    text: readString(json, 'text'),
    author: json['author'] as String?,
    day: json['day'] == null ? null : parseDate(json['day'], 'day'),
    createdAt: parseTimestampOrNull(json['createdAt'], 'createdAt'),
    updatedAt: parseTimestampOrNull(json['updatedAt'], 'updatedAt'),
    loved: json['loved'] as bool? ?? false,
    lovedAt: parseTimestampOrNull(json['lovedAt'], 'lovedAt'),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'author': author,
    'day': day == null ? null : dateKey(day!),
    'createdAt': createdAt == null ? null : formatTimestamp(createdAt!),
    'updatedAt': updatedAt == null ? null : formatTimestamp(updatedAt!),
    'loved': loved,
    if (lovedAt != null) 'lovedAt': formatTimestamp(lovedAt!),
  };

  /// A copy with [loved] set; [lovedAt] is kept when loved, cleared
  /// otherwise (unless given).
  Quote withLoved(bool loved, {DateTime? lovedAt}) => Quote(
    id: id,
    text: text,
    author: author,
    day: day,
    createdAt: createdAt,
    updatedAt: updatedAt,
    loved: loved,
    lovedAt: loved ? (lovedAt ?? this.lovedAt) : null,
  );

  /// "— Author", or "— Unknown" for anonymous quotes.
  String get attribution => '— ${author ?? 'Unknown'}';

  @override
  bool operator ==(Object other) =>
      other is Quote &&
      other.id == id &&
      other.text == text &&
      other.author == author &&
      other.day == day &&
      other.loved == loved &&
      other.lovedAt == lovedAt;

  @override
  int get hashCode => Object.hash(id, text, author, day, loved, lovedAt);

  @override
  String toString() => 'Quote($id, "$text", $author, loved: $loved)';
}

/// `GET /quotes?date=` — the quote for [date]; [fallback] when no quote is
/// scheduled that day and the server picked one deterministically.
class DailyQuote {
  final DateTime date;
  final bool fallback;
  final Quote quote;

  const DailyQuote({
    required this.date,
    required this.fallback,
    required this.quote,
  });

  factory DailyQuote.fromJson(Map<String, dynamic> json) => DailyQuote(
    date: parseDate(json['date'], 'date'),
    fallback: json['fallback'] as bool? ?? false,
    quote: Quote.fromJson(readObject(json, 'quote')),
  );

  Map<String, dynamic> toJson() => {
    'date': dateKey(date),
    'fallback': fallback,
    'quote': quote.toJson(),
  };

  DailyQuote withQuote(Quote quote) =>
      DailyQuote(date: date, fallback: fallback, quote: quote);
}

/// `GET /quotes?past=N` or `?from=&to=` — the scheduled quotes of past
/// days, newest day first.
class QuoteHistory {
  final DateTime from;
  final DateTime to;
  final List<Quote> items;

  const QuoteHistory({
    required this.from,
    required this.to,
    required this.items,
  });

  factory QuoteHistory.fromJson(Map<String, dynamic> json) => QuoteHistory(
    from: parseDate(json['from'], 'from'),
    to: parseDate(json['to'], 'to'),
    items: [for (final q in readObjectList(json, 'items')) Quote.fromJson(q)],
  );
}
