import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/remote/api_exception.dart';
import 'package:habit_quest/data/remote/fake_quotes_api.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/data/sync/string_store.dart';
import 'package:habit_quest/domain/providers.dart';
import 'package:habit_quest/features/quotes/quotes_providers.dart';

import '../../helpers/test_app.dart';

/// Sunday 2026-10-18, noon (same calendar day in UTC).
DateTime clock() => DateTime(2026, 10, 18, 12);

const _offline = ApiException(
  code: ApiException.networkError,
  message: 'offline',
);

class _Harness {
  _Harness({Map<String, DateTime>? loves})
    : api = FakeQuotesApi(now: clock, loves: loves);

  final FakeQuotesApi api;
  final store = MemoryStringStore();
  late final cache = QuotesCache(store);
  DateTime Function() now = clock;

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        ...signedInOverrides(),
        habitRepositoryProvider.overrideWithValue(InMemoryHabitRepository()),
        clockProvider.overrideWithValue(() => now()),
        quotesApiProvider.overrideWithValue(api),
        quotesCacheProvider.overrideWithValue(cache),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('asks for the LOCAL calendar day and caches the quote', () async {
    final h = _Harness();
    // 00:30 local on Oct 19 may still be Oct 18 in UTC: ask for Oct 19.
    h.now = () => DateTime(2026, 10, 19, 0, 30);
    final c = h.container();
    final daily = await c.read(todayQuoteProvider.future);

    expect(h.api.calls, ['quoteOfDay 2026-10-19']);
    expect(daily!.quote.id, 'q4');
    expect(h.cache.owner, testSession.user.id);
    expect(h.cache.dailyQuote!.quote.id, 'q4');
  });

  test(
    'offline: today\'s quote and the saved list come from the cache',
    () async {
      final h = _Harness();
      await h.api.love('q1');
      final online = h.container();
      await online.read(todayQuoteProvider.future);
      await online.read(savedQuotesProvider.future);

      // New app start, offline.
      h.api.offline = true;
      final offline = h.container();
      final daily = await offline.read(todayQuoteProvider.future);
      final saved = await offline.read(savedQuotesProvider.future);
      await settle();

      expect(daily!.quote.id, 'q3');
      expect(saved.map((q) => q.id), ['q1']);
      expect(offline.read(todayQuoteProvider).value!.quote.id, 'q3');
      expect(offline.read(savedQuotesProvider).value!.single.loved, isTrue);
    },
  );

  test('offline without a cache: an error, no crash', () async {
    final h = _Harness()..api.offline = true;
    final c = h.container();
    await expectLater(
      c.read(todayQuoteProvider.future),
      throwsA(isA<ApiException>()),
    );
    expect(c.read(todayQuoteProvider).hasError, isTrue);
  });

  test('a cached quote of another day is not shown as today\'s', () async {
    final h = _Harness();
    await h.cache.claim(testSession.user.id);
    await h.cache.saveDailyQuote(
      await h.api.quoteOfDay(DateTime(2026, 10, 17)),
    );
    final c = h.container();
    expect((await c.read(todayQuoteProvider.future))!.quote.id, 'q3');
  });

  test('another user\'s cache is ignored and cleared', () async {
    final h = _Harness();
    await h.cache.claim('someone-else');
    await h.cache.saveLovedQuotes([
      (await h.api.quoteOfDay(DateTime(2026, 10, 16))).quote.withLoved(true),
    ]);
    final c = h.container();
    expect(await c.read(savedQuotesProvider.future), isEmpty);
    expect(h.cache.owner, testSession.user.id);
    expect(h.cache.lovedQuotes, isEmpty);
  });

  test('no quotes on the server (404): today is null', () async {
    final h = _Harness();
    final c = ProviderContainer(
      overrides: [
        ...signedInOverrides(),
        habitRepositoryProvider.overrideWithValue(InMemoryHabitRepository()),
        clockProvider.overrideWithValue(clock),
        quotesApiProvider.overrideWithValue(FakeQuotesApi(quotes: const [])),
        quotesCacheProvider.overrideWithValue(h.cache),
      ],
    );
    addTearDown(c.dispose);
    expect(await c.read(todayQuoteProvider.future), isNull);
  });

  test('past quotes: the local days before today, newest first', () async {
    final h = _Harness();
    final c = h.container();
    final sub = c.listen(pastQuotesProvider, (_, _) {});
    addTearDown(sub.close);
    final past = await c.read(pastQuotesProvider.future);
    expect(h.api.calls, ['quotesBetween 2026-09-18 2026-10-17']);
    expect(past.map((q) => q.id), ['q2', 'q1']);
  });

  group('love toggles', () {
    test('optimistic: everything flips before the server answers', () async {
      final h = _Harness();
      final c = h.container();
      final today = (await c.read(todayQuoteProvider.future))!.quote;
      await c.read(savedQuotesProvider.future);

      h.api.pause = Completer<void>();
      final pending = c.read(quoteLoveControllerProvider).toggle(today);
      await settle();

      expect(h.api.calls.last, 'love q3');
      expect(c.read(quoteLovedProvider(today)), isTrue);
      expect(c.read(savedQuotesProvider).value!.map((q) => q.id), ['q3']);
      // A second tap while in flight is ignored.
      expect(await c.read(quoteLoveControllerProvider).toggle(today), isNull);

      h.api.pause!.complete();
      expect(await pending, isTrue);
      expect(h.api.lovedIds, {'q3'});
      expect(c.read(todayQuoteProvider).value!.quote.loved, isTrue);
      // Persisted for offline use.
      expect(h.cache.dailyQuote!.quote.loved, isTrue);
      expect(h.cache.lovedQuotes!.single.id, 'q3');
      expect(h.cache.lovedQuotes!.single.lovedAt, isNotNull);
    });

    test('rollback: a failed love restores the previous state', () async {
      final h = _Harness();
      final c = h.container();
      final today = (await c.read(todayQuoteProvider.future))!.quote;
      await c.read(savedQuotesProvider.future);

      h.api.pause = Completer<void>();
      h.api.failNextWith = _offline;
      final pending = c.read(quoteLoveControllerProvider).toggle(today);
      await settle();
      expect(c.read(quoteLovedProvider(today)), isTrue);

      h.api.pause!.complete();
      await expectLater(pending, throwsA(isA<ApiException>()));
      expect(c.read(quoteLovedProvider(today)), isFalse);
      expect(c.read(savedQuotesProvider).value, isEmpty);
      expect(h.api.lovedIds, isEmpty);
      expect(h.cache.dailyQuote!.quote.loved, isFalse);
    });

    test('rollback: a failed unlove puts the quote back in place', () async {
      final h = _Harness(
        loves: {
          'q1': DateTime.utc(2026, 10, 17, 8),
          'q2': DateTime.utc(2026, 10, 18, 8),
        },
      );
      final c = h.container();
      final saved = await c.read(savedQuotesProvider.future);
      expect(saved.map((q) => q.id), ['q2', 'q1']);

      h.api.failNextWith = const ApiException(
        status: 500,
        code: ApiException.internalError,
        message: 'boom',
      );
      await expectLater(
        c.read(quoteLoveControllerProvider).setLoved(saved.first, false),
        throwsA(isA<ApiException>()),
      );
      expect(c.read(savedQuotesProvider).value, saved);
      expect(c.read(quoteLovedProvider(saved.first)), isTrue);

      // And a successful unlove removes it everywhere.
      await c.read(quoteLoveControllerProvider).setLoved(saved.first, false);
      expect(c.read(savedQuotesProvider).value!.map((q) => q.id), ['q1']);
      expect(h.cache.lovedQuotes!.map((q) => q.id), ['q1']);
      expect(h.api.lovedIds, {'q1'});
    });
  });
}
