import 'package:flutter/material.dart';

import '../../core/widgets/placeholder_screen.dart';

/// Habit details (`/habits/:id`). Placeholder: built by the details task.
class HabitDetailsScreen extends StatelessWidget {
  final String habitId;

  const HabitDetailsScreen({super.key, required this.habitId});

  @override
  Widget build(BuildContext context) {
    return PlaceholderScreen(
      title: 'Habit',
      emoji: '🔥',
      message: 'Details for habit $habitId',
    );
  }
}
