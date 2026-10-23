import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/router/app_router.dart';
import 'package:habit_quest/core/router/auth_redirect.dart';
import 'package:habit_quest/data/remote/fake_account_api.dart';
import 'package:habit_quest/data/remote/fake_auth_api.dart';
import 'package:habit_quest/data/remote/fake_quotes_api.dart';
import 'package:habit_quest/features/auth/auth_providers.dart';
import 'package:habit_quest/features/auth/login_screen.dart';
import 'package:habit_quest/features/auth/session_store.dart';
import 'package:habit_quest/features/quotes/public_quote_screen.dart';
import 'package:habit_quest/features/quotes/quotes_screen.dart';
import 'package:habit_quest/features/widgets_bridge/widget_links.dart';

import '../../helpers/test_app.dart';

/// Sunday 2026-10-18, noon: the sample quote of the day is `q3`.
DateTime clock() => DateTime(2026, 10, 18, 12);
const q3Text = 'Little by little, one travels far.';

String location(ProviderContainer c) =>
    c.read(routerProvider).routerDelegate.currentConfiguration.uri.toString();

void main() {
  group('auth gate allow-list (signed out)', () {
    const out = SignedOut();
    Uri u(String s) => Uri.parse(s);

    test('only /quote is allowed signed out', () {
      expect(authRedirect(out, u('/quote')), isNull);
      expect(authRedirect(out, u('/login')), isNull);
      for (final p in ['/habits', '/calendar', '/quest', '/profile']) {
        expect(authRedirect(out, u(p)), startsWith('/login'), reason: p);
      }
      expect(
        authRedirect(out, u('/quotes/saved')),
        '/login?from=%2Fquotes%2Fsaved',
      );
      expect(
        authRedirect(out, u('/habits/quotes/saved')),
        startsWith('/login'),
      );
      expect(authRedirect(out, u('/habits/h1')), startsWith('/login'));
    });

    test('the quote locations (widget link) open /quote', () {
      expect(authRedirect(out, u('/habits/quotes')), '/quote');
      expect(authRedirect(out, u('/quotes')), '/quote');
      // Cold start: splash keeps the widget target, then /quote.
      expect(
        authRedirect(const AuthUnknown(), u('/habits/quotes')),
        '/splash?from=%2Fhabits%2Fquotes',
      );
      expect(authRedirect(out, u('/splash?from=%2Fhabits%2Fquotes')), '/quote');
      expect(
        authRedirect(const AuthUnknown(), u('/quote')),
        '/splash?from=%2Fhabits%2Fquotes',
      );
      // The widget URI maps to /habits/quotes first.
      expect(
        widgetDeepLinkLocation(Uri.parse('habitquest://quotes')),
        '/habits/quotes',
      );
    });

    test('login stays on login, keeping its return location', () {
      expect(authRedirect(out, u('/login?from=%2Fhabits%2Fquotes')), isNull);
    });

    test('signed in: /quote → the Quotes screen above Habits', () {
      final signedIn = SignedIn(testSession);
      expect(authRedirect(signedIn, u('/quote')), '/habits/quotes');
      expect(authRedirect(signedIn, u('/habits/quotes')), isNull);
      expect(
        authRedirect(signedIn, u('/login?from=%2Fhabits%2Fquotes')),
        '/habits/quotes',
      );
      expect(safeReturnLocation('/quote'), '/habits/quotes');
    });
  });

  group('signed-out quote screen', () {
    late FakeAuthApi auth;
    late InMemorySessionStore sessions;
    late FakeQuotesApi quotes;

    Future<ProviderContainer> pumpSignedOut(
      WidgetTester tester, {
      String initialLocation = '/habits/quotes',
    }) {
      auth = FakeAuthApi()..addUser('hero@example.com', 'secret1');
      sessions = InMemorySessionStore();
      quotes = FakeQuotesApi(now: clock);
      return pumpHabitQuestApp(
        tester,
        signedIn: false,
        clock: clock,
        initialLocation: initialLocation,
        quotesApi: quotes,
        overrides: [
          authApiProvider.overrideWithValue(auth),
          accountApiProvider.overrideWithValue(FakeAccountApi()),
          sessionStoreProvider.overrideWithValue(sessions),
          authControllerProvider.overrideWith(
            () => AuthController(proactiveRefresh: false),
          ),
          backendConfigOverride,
        ],
      );
    }

    testWidgets('the widget link shows today\'s quote, not the login', (
      tester,
    ) async {
      final c = await pumpSignedOut(tester);
      expect(location(c), '/quote');
      expect(find.byType(PublicQuoteScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text('“$q3Text”'), findsOneWidget);
      expect(quotes.calls, contains('quoteOfDay 2026-10-18'));
    });

    testWidgets('app-bar Back goes to the login screen', (tester) async {
      final c = await pumpSignedOut(tester);
      await tester.tap(find.byKey(const ValueKey('public-quote-back')));
      await tester.pumpAndSettle();
      expect(location(c), '/login');
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('system Back goes to the login screen (no exit, no loop)', (
      tester,
    ) async {
      final c = await pumpSignedOut(tester, initialLocation: '/quote');
      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handled, isTrue);
      expect(location(c), '/login');
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(PublicQuoteScreen), findsNothing);
    });

    testWidgets('heart → login → sign in → back on the quote, loved', (
      tester,
    ) async {
      final c = await pumpSignedOut(tester);
      await tester.tap(find.byKey(const ValueKey('public-love-q3')));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(location(c), '/login?from=%2Fhabits%2Fquotes');
      expect(quotes.lovedIds, isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('auth-email')),
        'hero@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'secret1',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();

      expect(location(c), '/habits/quotes');
      expect(find.byType(QuotesScreen), findsOneWidget);
      expect(quotes.lovedIds, {'q3'});
      final heart = tester.widget<IconButton>(
        find.byKey(const ValueKey('today-love-q3')),
      );
      expect(heart.isSelected, isTrue);
      expect(find.byKey(const ValueKey('pending-love-done')), findsOneWidget);

      // Back from Quotes lands on Habits (the normal signed-in stack).
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(location(c), '/habits');
    });
  });

  testWidgets('signed in, the widget link still opens the Quotes screen', (
    tester,
  ) async {
    final c = await pumpHabitQuestApp(
      tester,
      clock: clock,
      initialLocation: '/habits/quotes',
      quotesApi: FakeQuotesApi(now: clock),
    );
    expect(location(c), '/habits/quotes');
    expect(find.byType(QuotesScreen), findsOneWidget);
    expect(find.byType(PublicQuoteScreen), findsNothing);
  });
}
