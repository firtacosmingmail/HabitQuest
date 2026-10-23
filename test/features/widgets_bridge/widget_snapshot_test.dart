import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/utils/dates.dart';
import 'package:habit_quest/data/models/completion_log.dart';
import 'package:habit_quest/data/models/quote.dart';
import 'package:habit_quest/features/widgets_bridge/widget_constants.dart';
import 'package:habit_quest/features/widgets_bridge/widget_snapshot.dart';

import '../../helpers/fixtures.dart';

void main() {
  final now = DateTime(2026, 10, 17, 9, 30);
  final today = d(2026, 10, 17);
  const quote = Quote(id: 'q1', text: 'Keep going.', author: 'Ada');

  group('buildWidgetSnapshot', () {
    test('ok: due habits with done flags for today and the quote', () {
      final s = buildWidgetSnapshot(
        signedIn: true,
        today: today,
        dueToday: [habit(id: 'a', name: 'Walk'), habit(id: 'b')],
        log: log({
          'a': [today],
          'b': [d(2026, 10, 16)], // yesterday does not count
        }),
        quote: quote,
        now: now,
      );
      expect(s.state, WidgetSnapshotState.ok);
      expect(s.date, '2026-10-17');
      expect(s.version, WidgetConstants.snapshotSchemaVersion);
      expect(s.habits.map((h) => (h.id, h.done)), [('a', true), ('b', false)]);
      expect(s.habits.first.name, 'Walk');
      expect(s.habits.first.emoji, '💧');
      expect(s.habits.first.color, 0xFF4CC9F0);
      expect(s.habits.first.colorHex, '#4CC9F0');
      expect(s.doneCount, 1);
      expect(s.quote, const WidgetQuote(text: 'Keep going.', author: 'Ada'));
    });

    test('signedOut: no habits, whatever is passed', () {
      final s = buildWidgetSnapshot(
        signedIn: false,
        today: today,
        dueToday: [habit()],
        log: const CompletionLog.empty(),
        now: now,
      );
      expect(s.state, WidgetSnapshotState.signedOut);
      expect(s.habits, isEmpty);
      expect(s.quote, isNull);
    });

    test('signedOut with a quote: the quote is kept (Daily quote widget)', () {
      final s = buildWidgetSnapshot(
        signedIn: false,
        today: today,
        dueToday: [habit()],
        log: const CompletionLog.empty(),
        quote: const Quote(id: 'q', text: 'Keep going.', author: 'Ada'),
        quoteDay: today,
        now: now,
      );
      expect(s.state, WidgetSnapshotState.signedOut);
      expect(s.habits, isEmpty);
      final decoded = WidgetSnapshot.tryDecode(s.encode())!;
      expect(decoded.state, WidgetSnapshotState.signedOut);
      expect(decoded.quote!.text, 'Keep going.');
      expect(decoded.quote!.author, 'Ada');
      expect(decoded.quote!.day, dateKey(today));
      // Rolling over keeps the quote (its day says it is yesterday's).
      final rolled = decoded.rolledOverTo(dateKey(today.add(const Duration(days: 1))));
      expect(rolled.state, WidgetSnapshotState.signedOut);
      expect(rolled.quote!.text, 'Keep going.');
    });

    test('noHabits: signed in, nothing due today', () {
      final s = buildWidgetSnapshot(
        signedIn: true,
        today: today,
        dueToday: const [],
        log: const CompletionLog.empty(),
        quote: quote,
        now: now,
      );
      expect(s.state, WidgetSnapshotState.noHabits);
      expect(s.habits, isEmpty);
      expect(s.quote?.text, 'Keep going.');
    });

    test('archived habits are left out (all archived = noHabits)', () {
      final s = buildWidgetSnapshot(
        signedIn: true,
        today: today,
        dueToday: [habit(archived: true)],
        log: const CompletionLog.empty(),
        now: now,
      );
      expect(s.state, WidgetSnapshotState.noHabits);
    });

    test('no quote: quote is null; anonymous author is null', () {
      final noQuote = buildWidgetSnapshot(
        signedIn: true,
        today: today,
        dueToday: [habit()],
        log: const CompletionLog.empty(),
        now: now,
      );
      expect(noQuote.quote, isNull);
      expect(noQuote.toJson()['quote'], isNull);

      final anonymous = buildWidgetSnapshot(
        signedIn: true,
        today: today,
        dueToday: [habit()],
        log: const CompletionLog.empty(),
        quote: const Quote(id: 'q', text: 'Proverb.'),
        now: now,
      );
      expect(anonymous.quote!.author, isNull);
      expect(anonymous.quote!.attribution, '— Unknown');
    });
  });

  test('JSON matches the documented schema and round-trips', () {
    final s = buildWidgetSnapshot(
      signedIn: true,
      today: today,
      dueToday: [habit(id: 'h 1')],
      log: log({
        'h 1': [today],
      }),
      quote: quote,
      quoteDay: today,
      allHabits: [habit(id: 'h 1')],
      now: now,
    );
    final json = jsonDecode(s.encode()) as Map<String, dynamic>;
    expect(json.keys, [
      'version',
      'date',
      'generatedAt',
      'state',
      'habits',
      'doneCount',
      'totalCount',
      'quote',
      'upcoming',
    ]);
    expect(json['state'], 'ok');
    expect(json['generatedAt'], now.toUtc().toIso8601String());
    expect(json['doneCount'], 1);
    expect(json['totalCount'], 1);
    expect(json['habits'], [
      {
        'id': 'h 1',
        'name': 'Drink water',
        'emoji': '💧',
        'color': 0xFF4CC9F0,
        'colorHex': '#4CC9F0',
        'done': true,
        'toggleUri': 'habitquest://widget/toggle?habitId=h+1',
      },
    ]);
    expect(json['quote'], {
      'text': 'Keep going.',
      'author': 'Ada',
      'attribution': '— Ada',
      'day': dateKey(today),
    });
    // The next days' due habits, precomputed for the roll-over.
    final upcoming = json['upcoming'] as List;
    expect(upcoming, hasLength(WidgetSnapshot.upcomingDayCount));
    expect(upcoming.first['date'], dateKey(today.add(const Duration(days: 1))));
    expect(upcoming.first['habits'][0]['id'], 'h 1');
    expect(upcoming.first['habits'][0]['done'], isFalse);
    expect(Uri.parse(json['habits'][0]['toggleUri'] as String)
        .queryParameters['habitId'], 'h 1');

    final back = WidgetSnapshot.tryDecode(s.encode())!;
    expect(back.sameContentAs(s), isTrue);
    expect(WidgetSnapshot.tryDecode('not json'), isNull);
    expect(WidgetSnapshot.tryDecode(null), isNull);
  });
}
