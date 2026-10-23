/// Route paths. Prefer these helpers over string literals.
abstract final class AppRoutes {
  static const habits = '/habits';
  static const calendar = '/calendar';
  static const quest = '/quest';
  static const newHabit = '/habits/new';
  static const login = '/login';
  static const profile = '/profile';
  static const splash = '/splash';

  /// Today's quote and the past days' quotes.
  static const quotes = '/quotes';

  /// Today's quote for signed-out users (the Daily quote widget's link
  /// while signed out). The only route the auth gate allows signed out;
  /// signed in it redirects to [habitsQuotes].
  static const publicQuote = '/quote';

  /// The user's loved quotes.
  static const savedQuotes = '/quotes/saved';

  /// The Quotes screen stacked on the Habits tab: where a widget's quote link
  /// lands, so that Back returns to Habits. (`/quotes` alone would replace
  /// the whole stack: Back would then send the app to the background while it
  /// still shows Quotes, and the next launcher start would show it again.)
  static const habitsQuotes = '/habits/quotes';

  /// [savedQuotes] stacked on [habitsQuotes] (widget link).
  static const habitsSavedQuotes = '/habits/quotes/saved';

  /// Email confirmation deep link (`habitquest://auth-callback?...`).
  static const authCallback = '/auth-callback';

  static String habitDetails(String id) => '/habits/$id';
  static String editHabit(String id) => '/habits/$id/edit';
}
