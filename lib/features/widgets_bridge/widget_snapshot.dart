import 'dart:convert';

import '../../core/utils/dates.dart';
import '../../data/models/completion_log.dart';
import '../../data/models/habit.dart';
import '../../data/models/quote.dart';
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

  const WidgetQuote({required this.text, this.author});

  factory WidgetQuote.fromQuote(Quote quote) =>
      WidgetQuote(text: quote.text, author: quote.author);

  /// "— Author" or "— Unknown" (same as `Quote.attribution`).
  String get attribution => '— ${author ?? 'Unknown'}';

  Map<String, dynamic> toJson() => {
        'text': text,
        'author': author,
        'attribution': attribution,
      };

  factory WidgetQuote.fromJson(Map<String, dynamic> json) => WidgetQuote(
        text: json['text'] as String,
        author: json['author'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is WidgetQuote && other.text == text && other.author == author;

  @override
  int get hashCode => Object.hash(text, author);
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

  const WidgetSnapshot({
    this.version = WidgetConstants.snapshotSchemaVersion,
    required this.date,
    required this.generatedAt,
    required this.state,
    this.habits = const [],
    this.quote,
  });

  int get doneCount => habits.where((h) => h.done).length;

  WidgetSnapshot copyWith({
    String? date,
    DateTime? generatedAt,
    List<WidgetHabit>? habits,
  }) =>
      WidgetSnapshot(
        version: version,
        date: date ?? this.date,
        generatedAt: generatedAt ?? this.generatedAt,
        state: state,
        habits: habits ?? this.habits,
        quote: quote,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'date': date,
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'state': state.wire,
        'habits': [for (final h in habits) h.toJson()],
        'doneCount': doneCount,
        'totalCount': habits.length,
        'quote': quote?.toJson(),
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
  bool sameContentAs(WidgetSnapshot other) {
    if (version != other.version ||
        date != other.date ||
        state != other.state ||
        quote != other.quote ||
        habits.length != other.habits.length) {
      return false;
    }
    for (var i = 0; i < habits.length; i++) {
      if (habits[i] != other.habits[i]) return false;
    }
    return true;
  }
}

/// Pure snapshot builder.
///
/// * [signedIn] false → `signedOut` (no habits; the quote is kept if given).
/// * [dueToday] empty → `noHabits`.
/// * Otherwise `ok`, with `done` read from [log] for [today].
WidgetSnapshot buildWidgetSnapshot({
  required bool signedIn,
  required DateTime today,
  required List<Habit> dueToday,
  required CompletionLog log,
  Quote? quote,
  required DateTime now,
}) {
  final day = dateOnly(today);
  final widgetQuote = quote == null ? null : WidgetQuote.fromQuote(quote);
  if (!signedIn) {
    return WidgetSnapshot(
      date: dateKey(day),
      generatedAt: now.toUtc(),
      state: WidgetSnapshotState.signedOut,
      quote: widgetQuote,
    );
  }
  final habits = [
    for (final h in dueToday)
      if (!h.archived && !h.isDeleted)
        WidgetHabit(
          id: h.id,
          name: h.name,
          emoji: h.emoji,
          color: h.colorValue,
          done: log.isCompleted(h.id, day),
        ),
  ];
  return WidgetSnapshot(
    date: dateKey(day),
    generatedAt: now.toUtc(),
    state: habits.isEmpty ? WidgetSnapshotState.noHabits : WidgetSnapshotState.ok,
    habits: habits,
    quote: widgetQuote,
  );
}
