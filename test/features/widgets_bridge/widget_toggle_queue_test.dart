import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/models/completion_log.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/domain/habit_events.dart';
import 'package:habit_quest/domain/habit_service.dart';
import 'package:habit_quest/features/widgets_bridge/widget_constants.dart';
import 'package:habit_quest/features/widgets_bridge/widget_snapshot.dart';
import 'package:habit_quest/features/widgets_bridge/widget_store.dart';
import 'package:habit_quest/features/widgets_bridge/widget_toggle_queue.dart';

import '../../helpers/fixtures.dart';

void main() {
  final now = DateTime(2026, 10, 17, 9);
  final today = d(2026, 10, 17);

  MemoryWidgetStore storeWith({
    String date = '2026-10-17',
    Map<String, bool> done = const {'a': false, 'b': true},
  }) {
    final snapshot = buildWidgetSnapshot(
      signedIn: true,
      today: parseDay(date),
      dueToday: [for (final id in done.keys) habit(id: id)],
      log: CompletionLog.fromDates({
        for (final e in done.entries)
          if (e.value) e.key: [parseDay(date)],
      }),
      now: now,
    );
    return MemoryWidgetStore({WidgetConstants.snapshotKey: snapshot.encode()});
  }

  WidgetSnapshot snapshotOf(MemoryWidgetStore store) =>
      WidgetSnapshot.tryDecode(store.data[WidgetConstants.snapshotKey])!;

  var ids = 0;
  String nextId() => 't${ids++}';

  group('recordWidgetToggle (background isolate)', () {
    test('flips done in the snapshot, queues the wanted state, refreshes',
        () async {
      final store = storeWith();
      final t = await recordWidgetToggle(store, 'a', now: now, newId: nextId);
      expect(t!.habitId, 'a');
      expect(t.date, '2026-10-17');
      expect(t.done, isTrue);
      expect(snapshotOf(store).habits.map((h) => h.done), [true, true]);
      expect(store.refreshCount, 1);

      await recordWidgetToggle(store, 'b', now: now, newId: nextId);
      final queue = await readToggleQueue(store);
      expect(queue.map((q) => (q.habitId, q.done)), [('a', true), ('b', false)]);
      expect(snapshotOf(store).habits.map((h) => h.done), [true, false]);
    });

    test('ignores unknown habits, a missing snapshot and non-ok states',
        () async {
      expect(await recordWidgetToggle(storeWith(), 'zz', now: now), isNull);
      expect(await recordWidgetToggle(MemoryWidgetStore(), 'a', now: now),
          isNull);
      final signedOut = MemoryWidgetStore({
        WidgetConstants.snapshotKey: buildWidgetSnapshot(
          signedIn: false,
          today: today,
          dueToday: const [],
          log: const CompletionLog.empty(),
          now: now,
        ).encode(),
      });
      expect(await recordWidgetToggle(signedOut, 'a', now: now), isNull);
      expect(signedOut.data[WidgetConstants.toggleQueueKey], isNull);
    });

    test('a snapshot from an earlier day is rolled over to today', () async {
      final store = storeWith(date: '2026-10-16', done: {'a': true, 'b': true});
      final t = await recordWidgetToggle(store, 'a', now: now);
      expect(t!.date, '2026-10-17');
      expect(t.done, isTrue); // yesterday's "done" does not carry over
      final s = snapshotOf(store);
      expect(s.date, '2026-10-17');
      expect(s.habits.map((h) => h.done), [true, false]);
    });

    test('handleWidgetInteraction only handles toggle URIs', () async {
      final store = storeWith();
      expect(
        await handleWidgetInteraction(Uri.parse(WidgetConstants.quotesUri),
            store, now: now),
        isNull,
      );
      expect(await handleWidgetInteraction(null, store, now: now), isNull);
      final t = await handleWidgetInteraction(
        Uri.parse(WidgetConstants.toggleUri('a')),
        store,
        now: now,
      );
      expect(t?.habitId, 'a');
    });
  });

  group('applyPendingToggles (app)', () {
    late InMemoryHabitRepository repo;
    late HabitService service;
    late List<CompletionEvent> events;

    setUp(() {
      repo = InMemoryHabitRepository(
        habits: [habit(id: 'a'), habit(id: 'b')],
        completions: {
          'b': [today],
        },
      );
      service = HabitService(repo, now: () => now);
      events = [];
      service.completionEvents.listen(events.add);
    });
    tearDown(() => service.dispose());

    MemoryWidgetStore queueStore(List<(String, String, bool)> entries) =>
        MemoryWidgetStore({
          WidgetConstants.toggleQueueKey: jsonEncode([
            for (final (i, e) in entries.indexed)
              PendingToggle(
                id: 'id$i',
                habitId: e.$1,
                date: e.$2,
                done: e.$3,
                at: now,
              ).toJson(),
          ]),
        });

    test('applies through HabitService (events for XP/streaks/sync) and '
        'empties the queue', () async {
      final store = queueStore([
        ('a', '2026-10-17', true),
        ('b', '2026-10-17', false),
      ]);
      expect(await applyPendingToggles(store, service), 2);
      await Future<void>.delayed(Duration.zero);
      expect(service.isCompleted('a', today), isTrue);
      expect(service.isCompleted('b', today), isFalse);
      expect(events, [
        CompletionEvent(habitId: 'a', date: today, completed: true),
        CompletionEvent(habitId: 'b', date: today, completed: false),
      ]);
      expect(store.data[WidgetConstants.toggleQueueKey], isNull);
    });

    test('collapses to the last wanted state per habit and day', () async {
      final store = queueStore([
        ('a', '2026-10-17', true),
        ('a', '2026-10-17', false),
        ('a', '2026-10-17', true),
      ]);
      expect(await applyPendingToggles(store, service), 1);
      expect(service.isCompleted('a', today), isTrue);
    });

    test('is idempotent: already-applied and repeated entries change nothing',
        () async {
      final store = queueStore([('b', '2026-10-17', true)]); // already done
      expect(await applyPendingToggles(store, service), 0);

      final again = queueStore([('a', '2026-10-17', true)]);
      final copy = MemoryWidgetStore({...again.data});
      expect(await applyPendingToggles(again, service), 1);
      expect(await applyPendingToggles(copy, service), 0); // delivered twice
      expect(await applyPendingToggles(again, service), 0); // queue is empty
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
    });

    test('a toggle on a past day (tapped before midnight) applies to that day',
        () async {
      final store = queueStore([('a', '2026-10-16', true)]);
      await applyPendingToggles(store, service);
      expect(service.isCompleted('a', d(2026, 10, 16)), isTrue);
      expect(service.isCompleted('a', today), isFalse);
    });

    test('drops unknown habits, future days and malformed entries', () async {
      final store = queueStore([
        ('gone', '2026-10-17', true),
        ('a', '2026-10-18', true),
      ]);
      final raw = jsonDecode(store.data[WidgetConstants.toggleQueueKey]!)
          as List;
      store.data[WidgetConstants.toggleQueueKey] =
          jsonEncode([...raw, {'bad': 1}]);
      expect(await applyPendingToggles(store, service), 0);
      expect(store.data[WidgetConstants.toggleQueueKey], isNull);
    });

    test('keeps toggles queued while the queue was being applied', () async {
      final store = _AppendingStore(queueStore([('a', '2026-10-17', true)]));
      await applyPendingToggles(store, service);
      final left = await readToggleQueue(store);
      expect(left.map((t) => t.id), ['late']);
    });
  });
}

DateTime parseDay(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Simulates the background isolate appending a toggle while the app
/// applies the queue (after the app's first read).
class _AppendingStore implements WidgetStore {
  final MemoryWidgetStore inner;
  int _reads = 0;

  _AppendingStore(this.inner);

  @override
  Future<String?> read(String key) async {
    if (key == WidgetConstants.toggleQueueKey && _reads++ == 1) {
      final list = jsonDecode(inner.data[key]!) as List;
      inner.data[key] = jsonEncode([
        ...list,
        PendingToggle(
          id: 'late',
          habitId: 'b',
          date: '2026-10-17',
          done: false,
          at: DateTime.utc(2026),
        ).toJson(),
      ]);
    }
    return inner.read(key);
  }

  @override
  Future<void> write(String key, String? value) => inner.write(key, value);

  @override
  Future<void> refreshWidgets() => inner.refreshWidgets();
}
