import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../game_rules.dart';

/// The mascot for a title band; it evolves as the player levels up.
String mascotForTitle(String title) => switch (title) {
  'Sprout' => '🌱',
  'Seeker' => '🧭',
  'Adventurer' => '🗡️',
  'Hero' => '🦸',
  'Champion' => '🏆',
  'Legend' => '🐉',
  'Mythic' => '✨',
  _ => '🌱',
};

/// The mascot for [level].
String mascotForLevel(int level) =>
    mascotForTitle(GameRules.titleForLevel(level));

/// Accent colour for a title band (used behind the mascot).
Color colorForTitle(String title) => switch (title) {
  'Sprout' => AppColors.mint,
  'Seeker' => AppColors.sky,
  'Adventurer' => AppColors.flame,
  'Hero' => AppColors.coral,
  'Champion' => AppColors.sunshine,
  'Legend' => AppColors.grape,
  'Mythic' => const Color(0xFFF15BB5),
  _ => AppColors.mint,
};

/// A round, softly glowing avatar showing the mascot for [title].
class MascotAvatar extends StatelessWidget {
  final String title;
  final double size;

  const MascotAvatar({super.key, required this.title, this.size = 96});

  @override
  Widget build(BuildContext context) {
    final color = colorForTitle(title);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [Colors.white, color.withValues(alpha: 0.55)],
        ),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: size / 5),
        ],
      ),
      child: Text(
        mascotForTitle(title),
        key: const ValueKey('mascot'),
        style: TextStyle(fontSize: size * 0.5),
      ),
    );
  }
}
