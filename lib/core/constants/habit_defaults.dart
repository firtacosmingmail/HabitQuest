/// Defaults and suggestions for creating habits.
abstract final class HabitDefaults {
  static const emoji = '⭐';

  /// Emoji offered by the emoji picker, grouped loosely by theme.
  static const emojiChoices = <String>[
    '⭐', '💧', '🏃', '🧘', '📚', '✍️', '🥗', '🍎', '😴', '🦷',
    '💪', '🚴', '🏊', '🚶', '🧠', '🎸', '🎨', '💊', '🧹', '🌱',
    '☀️', '🌙', '📵', '💰', '🙏', '❤️', '🐶', '🎯', '🔥', '🎮',
  ];

  /// Day labels for ISO weekdays 1 (Mon) … 7 (Sun).
  static const weekdayShort = <int, String>{
    1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun',
  };

  static const maxNameLength = 40;
}
