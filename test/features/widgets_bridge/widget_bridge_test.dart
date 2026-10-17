import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/router/app_routes.dart';
import 'package:habit_quest/data/remote/fake_auth_api.dart';
import 'package:habit_quest/data/remote/fake_quotes_api.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/domain/providers.dart';
import 'package:habit_quest/features/auth/auth_providers.dart';
import 'package:habit_quest/features/auth/session_store.dart';
import 'package:habit_quest/features/widgets_bridge/widget_bridge.dart';
import 'package:habit_quest/features/widgets_bridge/widget_constants.dart';
import 'package:habit_quest/features/widgets_bridge/widget_links.dart';
import 'package:habit_quest/features/widgets_bridge/widget_snapshot.dart';
import 'package:habit_quest/features/widgets_bridge/widget_store.dart';
import 'package:habit_quest/features/widgets_bridge/widget_toggle_queue.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  var now = DateTime(2026, 10, 17, 9);
  late MemoryWidgetStore store;
  late InMemoryHabitRepository repo;

  setUp(() {
    now = DateTime(2026, 10, 17, 9);
    store = MemoryWidgetStore();
    repo = InMemoryHabitRepository(
      habits: [habit(id: 'a', name: 'Walk'), habit(id: 'b')],
    );
  });

  ProviderContainer container({bool signedIn = true}) {
    final c = ProviderContainer(
      overrides: [
        if (signedIn)
          ...signedInOverrides()
        else ...[
          authApiProvider.overrideWithValue(FakeAuthApi()),
          sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
        ],
        habitRepositoryProvider.overrideWithValue(repo),
        clockProvider.overrideWithValue(() => now),
        quotesApiProvider.overrideWithValue(FakeQuotesApi(now: () => now)),
        widgetStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  WidgetSnapshot stored() =>
      WidgetSnapshot.tryDecode(store.data[WidgetConstants.snapshotKey])!;

  Future<WidgetBridge> started(ProviderContainer c) async {
    final bridge = c.read(widgetBridgeProvider)!;
    // Let auth and the habit streams load before the first write.
    c.listen(dueTodayProvider, (_, _) {});
    c.listen(completionsProvider, (_, _) {});
    await settle();
    await bridge.start();
    await settle();
    return bridge;
  }

  test('writes today\'s due habits on start and refreshes the widgets',
      () async {
    final c = container();
    await started(c);
    final s = stored();
    expect(s.state, WidgetSnapshotState.ok);
    expect(s.date, '2026-10-17');
    expect(s.habits.map((h) => (h.id, h.done)), [('a', false), ('b', false)]);
    expect(store.refreshCount, greaterThan(0));
  });

  test('rewrites the snapshot on a CompletionEvent', () async {
    final c = container();
    final bridge = await started(c);
    final before = store.refreshCount;
    await c.read(habitServiceProvider).toggleCompletion('a', d(2026, 10, 17));
    await settle();
    await bridge.writeNow();
    expect(stored().habits.first.done, isTrue);
    expect(store.refreshCount, greaterThan(before));
  });

  test('applies the queued widget check-offs on start', () async {
    store.data[WidgetConstants.toggleQueueKey] = jsonEncode([
      PendingToggle(
        id: 'x',
        habitId: 'b',
        date: '2026-10-17',
        done: true,
        at: now,
      ).toJson(),
    ]);
    final c = container();
    await started(c);
    expect(c.read(habitServiceProvider).isCompleted('b', d(2026, 10, 17)),
        isTrue);
    expect(store.data[WidgetConstants.toggleQueueKey], isNull);
    expect(stored().habits.last.done, isTrue);
  });

  test('signed out: writes the "Open HabitQuest" state', () async {
    final c = container(signedIn: false);
    await started(c);
    final s = stored();
    expect(s.state, WidgetSnapshotState.signedOut);
    expect(s.habits, isEmpty);
  });

  test('no habits: writes the noHabits state', () async {
    repo = InMemoryHabitRepository();
    final c = container();
    await started(c);
    expect(stored().state, WidgetSnapshotState.noHabits);
  });

  test('midnight rolls the snapshot over to the new day', () async {
    final c = container();
    await c.read(habitServiceProvider).toggleCompletion('a', d(2026, 10, 17));
    final bridge = await started(c);
    expect(stored().habits.first.done, isTrue);
    now = DateTime(2026, 10, 18, 0, 0, 2);
    bridge.onMidnight();
    await settle();
    await bridge.writeNow();
    expect(stored().date, '2026-10-18');
    expect(stored().habits.first.done, isFalse);
  });

  test('a toggle link that opened the app checks the habit once', () async {
    final c = container();
    await started(c);
    final handler = c.read(widgetLinkHandlerProvider);
    expect(await handler.toggle('a'), isTrue);
    expect(await handler.toggle('a'), isNull); // duplicate delivery
    expect(await handler.toggle('missing'), isNull);
    expect(c.read(habitServiceProvider).isCompleted('a', d(2026, 10, 17)),
        isTrue);
  });

  group('widget links', () {
    test('toggleHabitId reads only check-off URIs', () {
      expect(toggleHabitId(Uri.parse(WidgetConstants.toggleUri('a b'))), 'a b');
      expect(toggleHabitId(Uri.parse('habitquest://widget/toggle')), isNull);
      expect(toggleHabitId(Uri.parse(WidgetConstants.quotesUri)), isNull);
      expect(toggleHabitId(Uri.parse('https://x.y/widget/toggle?habitId=a')),
          isNull);
    });

    test('widgetDeepLinkLocation maps widget URIs to routes', () {
      expect(widgetDeepLinkLocation(Uri.parse(WidgetConstants.quotesUri)),
          AppRoutes.quotes);
      expect(widgetDeepLinkLocation(Uri.parse(WidgetConstants.openUri)),
          AppRoutes.habits);
      expect(
        widgetDeepLinkLocation(Uri.parse(WidgetConstants.toggleUri('a'))),
        AppRoutes.habits,
      );
      expect(widgetDeepLinkLocation(Uri.parse('/habits')), isNull);
      expect(
        widgetDeepLinkLocation(Uri.parse('habitquest://auth-callback')),
        isNull,
      );
    });
  });
}
