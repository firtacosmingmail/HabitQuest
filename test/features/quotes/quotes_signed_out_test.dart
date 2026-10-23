import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/remote/api_exception.dart';
import 'package:habit_quest/data/remote/fake_auth_api.dart';
import 'package:habit_quest/data/remote/fake_quotes_api.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/data/sync/string_store.dart';
import 'package:habit_quest/domain/providers.dart';
import 'package:habit_quest/features/auth/auth_providers.dart';
import 'package:habit_quest/features/auth/session_store.dart';
import 'package:habit_quest/features/quotes/quotes_providers.dart';

/// Sunday 2026-10-18, noon.
DateTime clock() => DateTime(2026, 10, 18, 12);

ProviderContainer signedOutContainer(FakeQuotesApi api, QuotesCache cache) {
  final c = ProviderContainer(
    overrides: [
      authApiProvider.overrideWithValue(FakeAuthApi()),
      sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
      authControllerProvider.overrideWith(
        () => AuthController(proactiveRefresh: false),
      ),
      habitRepositoryProvider.overrideWithValue(InMemoryHabitRepository()),
      clockProvider.overrideWithValue(clock),
      quotesApiProvider.overrideWithValue(api),
      quotesCacheProvider.overrideWithValue(cache),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> signedOut(ProviderContainer c) async {
  c.read(authControllerProvider);
  for (var i = 0; i < 20 && c.read(authControllerProvider) is! SignedOut; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(c.read(authControllerProvider), isA<SignedOut>());
}

void main() {
  test(
    'signed out: today\'s quote loads (loved false) and is cached',
    () async {
      // Even if the fake says "loved", a signed-out read is never loved.
      final api = FakeQuotesApi(now: clock, loves: {'q3': DateTime.utc(2026)});
      final cache = QuotesCache(MemoryStringStore());
      final c = signedOutContainer(api, cache);
      await signedOut(c);

      final daily = await c.read(todayQuoteProvider.future);
      expect(api.calls, ['quoteOfDay 2026-10-18']);
      expect(daily!.quote.id, 'q3');
      expect(daily.quote.loved, isFalse);
      expect(cache.owner, QuotesCache.anonymousOwner);
      expect(cache.dailyQuoteFor(DateTime(2026, 10, 18))!.quote.id, 'q3');
    },
  );

  test('signed out, offline or 401: the last cached quote is kept', () async {
    final api = FakeQuotesApi(now: clock);
    final cache = QuotesCache(MemoryStringStore());
    await cache.claim('previous-user');
    await cache.saveDailyQuote(
      await FakeQuotesApi(now: clock).quoteOfDay(DateTime(2026, 10, 17)),
    );
    api.failNextWith = const ApiException(
      status: 401,
      code: ApiException.unauthorized,
      message: 'not deployed yet',
    );
    final c = signedOutContainer(api, cache);
    await signedOut(c);

    final daily = await c.read(todayQuoteProvider.future);
    expect(daily!.quote.id, 'q2');
    expect(daily.quote.loved, isFalse);
  });

  test('signed out, offline without any cache: an error, no crash', () async {
    final api = FakeQuotesApi(now: clock)..offline = true;
    final c = signedOutContainer(api, QuotesCache(MemoryStringStore()));
    await signedOut(c);
    await expectLater(
      c.read(todayQuoteProvider.future),
      throwsA(isA<ApiException>()),
    );
  });
}
