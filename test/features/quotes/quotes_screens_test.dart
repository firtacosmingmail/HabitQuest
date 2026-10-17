import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/widgets/message_view.dart';
import 'package:habit_quest/data/remote/api_exception.dart';
import 'package:habit_quest/data/remote/fake_account_api.dart';
import 'package:habit_quest/data/remote/fake_quotes_api.dart';
import 'package:habit_quest/data/sync/string_store.dart';
import 'package:habit_quest/features/ads/ad_slot.dart';
import 'package:habit_quest/features/auth/auth_providers.dart';
import 'package:habit_quest/features/quotes/quotes_providers.dart';
import 'package:habit_quest/features/quotes/quotes_screen.dart';
import 'package:habit_quest/features/quotes/saved_quotes_screen.dart';
import 'package:habit_quest/features/quotes/widgets/quote_of_the_day_card.dart';

import '../../helpers/fake_ad_service.dart';
import '../../helpers/test_app.dart';

/// Sunday 2026-10-18, noon: q3 is scheduled today, q2 and q1 before.
DateTime clock() => DateTime(2026, 10, 18, 12);

const _todayText = 'Little by little, one travels far.';
const _q1Text = 'Well done is better than well said.';

Finder _key(String k) => find.byKey(ValueKey(k));

bool _isLoved(WidgetTester tester, String key) =>
    tester.widget<IconButton>(_key(key)).isSelected ?? false;

void main() {
  late FakeQuotesApi api;
  late QuotesCache cache;

  setUp(() {
    api = FakeQuotesApi(now: clock);
    cache = QuotesCache(MemoryStringStore());
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    String location = '/habits',
  }) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return pumpHabitQuestApp(
      tester,
      clock: clock,
      initialLocation: location,
      quotesApi: api,
      overrides: [
        quotesCacheProvider.overrideWithValue(cache),
        accountApiProvider.overrideWithValue(FakeAccountApi()),
        // Ads would show if a new screen asked for them.
        fakeAdsOverride(),
      ],
    );
  }

  testWidgets('Habits shows the Quote of the day card for the local day', (
    tester,
  ) async {
    await pump(tester);

    expect(_key('quote-of-the-day-card'), findsOneWidget);
    expect(find.text('Quote of the day'), findsOneWidget);
    expect(find.text('“$_todayText”'), findsOneWidget);
    expect(find.text('— Unknown'), findsOneWidget);
    expect(api.calls, contains('quoteOfDay 2026-10-18'));
    expect(_isLoved(tester, 'card-love-q3'), isFalse);

    await tester.tap(_key('card-love-q3'));
    await tester.pumpAndSettle();
    expect(_isLoved(tester, 'card-love-q3'), isTrue);
    expect(api.lovedIds, {'q3'});
    // The saved list on the device knows it too, for offline use.
    expect(cache.dailyQuote!.quote.loved, isTrue);
  });

  testWidgets('no quotes on the server: no card', (tester) async {
    api = FakeQuotesApi(quotes: const []);
    await pump(tester);
    expect(find.byType(QuoteOfTheDayCard), findsOneWidget);
    expect(_key('quote-of-the-day-card'), findsNothing);
  });

  testWidgets('tapping the card opens Quotes: today and past days, loved '
      'state shared with the card', (tester) async {
    await pump(tester);
    await tester.tap(_key('card-love-q3'));
    await tester.pumpAndSettle();

    await tester.tap(_key('card-quote-q3'));
    await tester.pumpAndSettle();
    expect(find.byType(QuotesScreen), findsOneWidget);
    expect(find.text('Today · Sun, Oct 18'), findsOneWidget);
    expect(_isLoved(tester, 'today-love-q3'), isTrue);
    expect(_key('past-quote-q2'), findsOneWidget);
    expect(_key('past-quote-q1'), findsOneWidget);
    expect(find.text('Sat, Oct 17'), findsOneWidget);
    // Newest day first.
    expect(
      tester.getTopLeft(_key('past-quote-q2')).dy,
      lessThan(tester.getTopLeft(_key('past-quote-q1')).dy),
    );
    expect(find.byType(AdFrame), findsNothing);

    // Unlove on the Quotes screen: the card follows.
    await tester.tap(_key('today-love-q3'));
    await tester.pumpAndSettle();
    expect(_isLoved(tester, 'today-love-q3'), isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_isLoved(tester, 'card-love-q3'), isFalse);
    expect(api.lovedIds, isEmpty);
  });

  testWidgets('love a past quote, find it in Saved, unlove it there', (
    tester,
  ) async {
    await pump(tester, location: '/quotes');

    await tester.tap(_key('past-love-q1'));
    await tester.pumpAndSettle();
    expect(_isLoved(tester, 'past-love-q1'), isTrue);

    await tester.tap(_key('saved-quotes-button'));
    await tester.pumpAndSettle();
    expect(find.byType(SavedQuotesScreen), findsOneWidget);
    expect(_key('saved-quote-q1'), findsOneWidget);
    expect(find.text('“$_q1Text”'), findsOneWidget);
    expect(find.text('— Benjamin Franklin'), findsOneWidget);
    expect(_isLoved(tester, 'saved-love-q1'), isTrue);
    expect(find.byType(AdFrame), findsNothing);

    await tester.tap(_key('saved-love-q1'));
    await tester.pumpAndSettle();
    expect(_key('saved-quote-q1'), findsNothing);
    expect(_key('saved-quotes-empty'), findsOneWidget);
    expect(find.byType(MessageView), findsOneWidget);
    expect(api.lovedIds, isEmpty);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_isLoved(tester, 'past-love-q1'), isFalse);
  });

  testWidgets('a failed love rolls back and says so', (tester) async {
    await pump(tester);
    api.failNextWith = const ApiException(
      code: ApiException.networkError,
      message: 'offline',
    );

    await tester.tap(_key('card-love-q3'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_isLoved(tester, 'card-love-q3'), isFalse);
    expect(_key('quote-love-error'), findsOneWidget);
    expect(find.textContaining("You're offline"), findsOneWidget);
    expect(api.lovedIds, isEmpty);
  });

  testWidgets('Saved quotes from Profile: empty state', (tester) async {
    await pump(tester, location: '/profile');

    await tester.ensureVisible(_key('profile-saved-quotes'));
    await tester.tap(_key('profile-saved-quotes'));
    await tester.pumpAndSettle();
    expect(find.byType(SavedQuotesScreen), findsOneWidget);
    expect(find.text('No saved quotes yet'), findsOneWidget);
    expect(_key('saved-quotes-empty'), findsOneWidget);
  });

  testWidgets('offline: the card and Saved show the device cache', (
    tester,
  ) async {
    // A previous online session filled the cache.
    await cache.claim(testSession.user.id);
    await api.love('q2');
    await cache.saveDailyQuote(await api.quoteOfDay(DateTime(2026, 10, 18)));
    await cache.saveLovedQuotes(await api.lovedQuotes());
    api.offline = true;

    await pump(tester);
    expect(find.text('“$_todayText”'), findsOneWidget);

    await tester.tap(_key('card-quote-q3'));
    await tester.pumpAndSettle();
    expect(find.text('“$_todayText”'), findsOneWidget);
    expect(_key('past-quotes-error'), findsOneWidget);

    await tester.tap(_key('open-saved-quotes'));
    await tester.pumpAndSettle();
    expect(_key('saved-quote-q2'), findsOneWidget);
    expect(_isLoved(tester, 'saved-love-q2'), isTrue);
  });

  testWidgets('a love from the card updates the cached saved list', (
    tester,
  ) async {
    await cache.claim(testSession.user.id);
    await cache.saveLovedQuotes(const []);
    await pump(tester);

    await tester.tap(_key('card-love-q3'));
    await tester.pumpAndSettle();
    expect(cache.lovedQuotes!.map((q) => q.id), ['q3']);
  });
}
