/// Route paths. Prefer these helpers over string literals.
abstract final class AppRoutes {
  static const habits = '/habits';
  static const calendar = '/calendar';
  static const quest = '/quest';
  static const newHabit = '/habits/new';
  static const login = '/login';
  static const profile = '/profile';
  static const splash = '/splash';

  /// Email confirmation deep link (`habitquest://auth-callback?...`).
  static const authCallback = '/auth-callback';

  static String habitDetails(String id) => '/habits/$id';
  static String editHabit(String id) => '/habits/$id/edit';
}
