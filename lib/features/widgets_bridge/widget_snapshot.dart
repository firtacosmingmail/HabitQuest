import 'dart:convert';

import '../../core/utils/dates.dart';
import '../../data/models/completion_log.dart';
import '../../data/models/habit.dart';
import '../../data/models/quote.dart';
import '../../domain/recurrence.dart';
import 'widget_constants.dart';

/// What the home-screen widgets show (schema: `docs/WIDGETS.md`).
enum WidgetSnapshotState {
  ok(WidgetConstants.stateOk),
  signedOut(WidgetConstants.stateSignedOut),
  noHabits(WidgetConstants.stateNoHabits);

  final String wire;

  const WidgetSnapshotState(this.wire);

  static WidgetSnapshotState fromWire(String? value) => values.firstWhere(
        (s) => s.wire == value,
        orElse: () => WidgetSnapshotState.signedOut,
      );
}

/// One due habit as the widgets see it.
class WidgetHabit {
  final String id;
  final String name;
  final String emoji;

  /// ARGB (`0xAARRGGBB`, unsigned: read it as a 64-bit integer natively).
  final int color;
  final bool done;

  const WidgetHabit({
    required this.id,
    required this.name,
    required this.emoji,
    required this.color,
    required this.done,
  });

  /// `#RRGGBB` (habit colours are opaque).
  String get colorHex =>
      '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  WidgetHabit copyWith({bool? done}) => WidgetHabit(
        id: id,
        name: name,
        emoji: emoji,
        color: color,
        done: done ?? this.done,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'color': color,
        'colorHex': colorHex,
        'done': done,
        'toggleUri': WidgetConstants.toggleUri(id),
      };

  factory WidgetHabit.fromJson(Map<String, dynamic> json) => WidgetHabit(
        id: json['id'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String,
        color: (json['color'] as num).toInt(),
        done: json['done'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is WidgetHabit &&
      other.id == id &&
      other.name == name &&
      other.emoji == emoji &&
      other.color == color &&
      other.done == done;

  @override
  int get hashCode => Object.hash(id, name, emoji, color, done);
}

/// Today's quote as the widgets see it.
class WidgetQuote {
  final String text;

  /// `null` for anonymous quotes.
  final String? author;

  /// The local day (`yyyy-MM-dd`) this is the quote of, or `null` when
  /// unknown (snapshots written before 2026-10-23). The background refresh
  /// fetches a new quote when it is not today.
  final String? day;

  const WidgetQuote({required this.text, this.author, this.day});

  factory WidgetQuote.fromQuote(Quote quote, {DateTime? day}) => WidgetQuote(
        text: quote.text,
        author: quote.author,
        day: day == null ? null : dateKey(day),
      );

  /// "— Author" or "— Unknown" (same as `Quote.attribution`).
  String get attribution => '— ${author ?? 'Unknown'}';

  Map<String, dynamic> toJson() => {
        'text': text,
        'author': author,
        'attribution': attribution,
        'day': day,
      };

  factory WidgetQuote.fromJson(Map<String, dynamic> json) => WidgetQuote(
        text: json['text'] as String,
        author: json['author'] as String?,
        day: json['day'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is WidgetQuote &&
      other.text == text &&
      other.author == author &&
      other.day == day;

  @override
  int get hashCode => Object.hash(text, author, day);
}

/// The habits due on a coming day, precomputed by the app from local data
/// so that the snapshot can roll over at midnight without the app (see
/// [WidgetSnapshot.rolledOverTo]).
class WidgetUpcomingDay {
  /// `yyyy-MM-dd` (local day).
  final String date;

  /// Due habits of [date], in app order, all not done.
  final List<WidgetHabit> habits;

  const WidgetUpcomingDay({required this.date, required this.habits});

  Map<String, dynamic> toJson() => {
        'date': date,
        'habits': [for (final h in habits) h.toJson()],
      };

  factory WidgetUpcomingDay.fromJson(Map<String, dynamic> json) =>
      WidgetUpcomingDay(
        date: json['date'] as String,
        habits: [
          for (final h in (json['habits'] as List? ?? const []))
            WidgetHabit.fromJson(Map<String, dynamic>.from(h as Map)),
        ],
      );
}

/// The whole widget payload, stored as one JSON string under
/// [WidgetConstants.snapshotKey].
class WidgetSnapshot {
  final int version;

  /// Local calendar day (`yyyy-MM-dd`) the habits and done flags are for.
  final String date;

  /// When the snapshot was written (UTC).
  final DateTime generatedAt;
  final WidgetSnapshotState state;

  /// Today's due habits (empty unless [state] is `ok`), in app order.
  final List<WidgetHabit> habits;
  final WidgetQuote? quote;

  /// The due habits of the next [upcomingDayCount] days (after [date]),
  /// oldest first; empty when signed out.
  final List<WidgetUpcomingDay> upcoming;

  const WidgetSnapshot({
    this.version = WidgetConstants.snapshotSchemaVersion,
    required this.date,
    required this.generatedAt,
    required this.state,
    this.habits = const [],
    this.quote,
    this.upcoming = const [],
  });

  /// How many coming days the app precomputes (covers a phone left alone
  /// for a week, e.g. in Doze, with the app never opened).
  static const upcomingDayCount = 7;

  int get doneCount => habits.where((h) => h.done).length;

  WidgetSnapshot copyWith({
    String? date,
    DateTime? generatedAt,
    WidgetSnapshotState? state,
    List<WidgetHabit>? habits,
    WidgetQuote? quote,
    bool clearQuote = false,
    List<WidgetUpcomingDay>? upcoming,
  }) =>
      WidgetSnapshot(
        version: version,
        date: date ?? this.date,
        generatedAt: generatedAt ?? this.generatedAt,
        state: state ?? this.state,
        habits: habits ?? this.habits,
        quote: clearQuote ? null : (quote ?? this.quote),
        upcoming: upcoming ?? this.upcoming,
      );

  /// This snapshot moved to the local day [todayKey] (`yyyy-MM-dd`) from
  /// local data only: the habits become that day's precomputed [upcoming]
  /// entry (all not done), or, past the precomputed window, the old list
  /// with every habit not done. The state follows (`ok` / `noHabits`;
  /// `signedOut` stays). The quote is kept: its `day` says whether it is
  /// still yesterday's. Returns `this` when [date] is not before [todayKey].
  WidgetSnapshot rolledOverTo(String todayKey) {
    // ISO dates compare correctly as strings.
    if (date.compareTo(todayKey) >= 0) return this;
    final later = [
      for (final u in upcoming)
        if (u.date.compareTo(todayKey) > 0) u,
    ];
    if (state == WidgetSnapshotState.signedOut) {
      return copyWith(date: todayKey, habits: const [], upcoming: const []);
    }
    final entry = upcoming.where((u) => u.date == todayKey).firstOrNull;
    final habits = entry != null
        ? [for (final h in entry.habits) h.copyWith(done: false)]
        : [for (final h in this.habits) h.copyWith(done: false)];
    return copyWith(
      date: todayKey,
      state: habits.isEmpty
          ? WidgetSnapshotState.noHabits
          : WidgetSnapshotState.ok,
      habits: habits,
      upcoming: later,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'date': date,
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'state': state.wire,
        'habits': [for (final h in habits) h.toJson()],
        'doneCount': doneCount,
        'totalCount': habits.length,
        'quote': quote?.toJson(),
        'upcoming': [for (final u in upcoming) u.toJson()],
      };

  String encode() => jsonEncode(toJson());

  factory WidgetSnapshot.fromJson(Map<String, dynamic> json) => WidgetSnapshot(
        version: (json['version'] as num?)?.toInt() ??
            WidgetConstants.snapshotSchemaVersion,
        date: json['date'] as String,
        generatedAt: DateTime.parse(json['generatedAt'] as String),
        state: WidgetSnapshotState.fromWire(json['state'] as String?),
        habits: [
          for (final h in (json['habits'] as List? ?? const []))
            WidgetHabit.fromJson(Map<String, dynamic>.from(h as Map)),
        ],
        quote: json['quote'] == null
            ? null
            : WidgetQuote.fromJson(
                Map<String, dynamic>.from(json['quote'] as Map),
              ),
        upcoming: [
          for (final u in (json['upcoming'] as List? ?? const []))
            WidgetUpcomingDay.fromJson(Map<String, dynamic>.from(u as Map)),
        ],
      );

  /// Parses [raw]; `null` if it is missing or unreadable.
  static WidgetSnapshot? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return WidgetSnapshot.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } on Object {
      return null;
    }
  }

  /// The same content ignoring [generatedAt] (to skip needless refreshes).
  bool sameContentAs(WidgetSnapshot other) =>
      _contentKey() == other._contentKey();

  String _contentKey() => jsonEncode(toJson()..remove('generatedAt'));
}

/// Pure snapshot builder.
///
/// * [signedIn] false → `signedOut` (no habits; the quote is kept if given).
/// * [dueToday] empty → `noHabits`.
/// * Otherwise `ok`, with `done` read from [log] for [today].
///
/// [quoteDay] is the day [quote] belongs to. When signed in and
/// [allHabits] is given, the due habits of the next
/// [WidgetSnapshot.upcomingDayCount] days are precomputed from it and [log]
/// (`upcoming`), so the snapshot can roll over without the app.
WidgetSnapshot buildWidgetSnapshot({
  required bool signedIn,
  required DateTime today,
  required List<Habit> dueToday,
  required CompletionLog log,
  Quote? quote,
  DateTime? quoteDay,
  Iterable<Habit>? allHabits,
  required DateTime now,
}) {
  final day = dateOnly(today);
  final widgetQuote =
      quote == null ? null : WidgetQuote.fromQuote(quote, day: quoteDay);
  if (!signedIn) {
    return WidgetSnapshot(
      date: dateKey(day),
      generatedAt: now.toUtc(),
      state: WidgetSnapshotState.signedOut,
      quote: widgetQuote,
    );
  }
  List<WidgetHabit> widgetHabits(Iterable<Habit> due, DateTime on) => [
        for (final h in due)
          if (!h.archived && !h.isDeleted)
            WidgetHabit(
              id: h.id,
              name: h.name,
              emoji: h.emoji,
              color: h.colorValue,
              done: log.isCompleted(h.id, on),
            ),
      ];
  final habits = widgetHabits(dueToday, day);
  final all = allHabits;
  return WidgetSnapshot(
    date: dateKey(day),
    generatedAt: now.toUtc(),
    state: habits.isEmpty ? WidgetSnapshotState.noHabits : WidgetSnapshotState.ok,
    habits: habits,
    quote: widgetQuote,
    upcoming: all == null
        ? const []
        : [
            for (var i = 1; i <= WidgetSnapshot.upcomingDayCount; i++)
              WidgetUpcomingDay(
                date: dateKey(addDays(day, i)),
                habits: widgetHabits(
                  dueHabitsOn(all, addDays(day, i), log),
                  addDays(day, i),
                ),
              ),
          ],
  );
}
