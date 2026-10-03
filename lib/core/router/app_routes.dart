/// Route paths. Prefer these helpers over string literals.
abstract final class AppRoutes {
  static const habits = '/habits';
  static const calendar = '/calendar';
  static const quest = '/quest';
  static const newHabit = '/habits/new';

  static String habitDetails(String id) => '/habits/$id';
  static String editHabit(String id) => '/habits/$id/edit';
}
