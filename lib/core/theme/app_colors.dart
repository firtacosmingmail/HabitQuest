import 'package:flutter/material.dart';

/// Brand colours for Habit Quest's playful look.
abstract final class AppColors {
  static const grape = Color(0xFF7C4DFF); // primary
  static const sunshine = Color(0xFFFFC93C); // secondary / XP gold
  static const coral = Color(0xFFFF6B6B); // tertiary / streak flame
  static const mint = Color(0xFF2EC4B6); // success / done
  static const sky = Color(0xFF4CC9F0);

  static const flame = Color(0xFFFF8C42);
  static const xpGold = sunshine;
  static const success = mint;
  static const perfectDay = Color(0xFFFFD166);
  /// Readable gold for Perfect Day text on light and dark surfaces.
  static const perfectDayInk = Color(0xFFB8860B);

  static const lightBackground = Color(0xFFFFF8F0);
  static const lightSurface = Color(0xFFFFFFFF);
  static const darkBackground = Color(0xFF17142B);
  static const darkSurface = Color(0xFF221E3D);
}

/// Colours a user can pick for a habit. Store `color.toARGB32()` in
/// `Habit.colorValue`.
abstract final class HabitPalette {
  static const colors = <Color>[
    Color(0xFFFF6B6B), // coral
    Color(0xFFFF8C42), // tangerine
    Color(0xFFFFC93C), // sunshine
    Color(0xFF8AC926), // lime
    Color(0xFF2EC4B6), // mint
    Color(0xFF4CC9F0), // sky
    Color(0xFF4361EE), // ocean
    Color(0xFF7C4DFF), // grape
    Color(0xFFC77DFF), // lavender
    Color(0xFFF15BB5), // bubblegum
    Color(0xFF9C6644), // cocoa
    Color(0xFF6C757D), // pebble
  ];

  static Color get defaultColor => colors[7];

  static int get defaultColorValue => defaultColor.toARGB32();

  /// Colour for a stored value, falling back to [defaultColor].
  static Color fromValue(int? value) =>
      value == null ? defaultColor : Color(value);

  /// Black or white, whichever reads better on [background].
  static Color onColor(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
          ? Colors.white
          : const Color(0xFF1B1B1F);
}
