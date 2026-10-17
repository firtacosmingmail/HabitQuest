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

  /// The user's loved quotes.
  static const savedQuotes = '/quotes/saved';

  /// Email confirmation deep link (`habitquest://auth-callback?...`).
  static const authCallback = '/auth-callback';

  static String habitDetails(String id) => '/habits/$id';
  static String editHabit(String id) => '/habits/$id/edit';
}
