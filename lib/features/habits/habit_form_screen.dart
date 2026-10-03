import 'package:flutter/material.dart';

import '../../core/widgets/placeholder_screen.dart';

/// Create (`/habits/new`, [habitId] == null) or edit (`/habits/:id/edit`)
/// a habit. Placeholder: built by the habits-screen task.
class HabitFormScreen extends StatelessWidget {
  final String? habitId;

  const HabitFormScreen({super.key, this.habitId});

  bool get isEditing => habitId != null;

  @override
  Widget build(BuildContext context) {
    return PlaceholderScreen(
      title: isEditing ? 'Edit habit' : 'New habit',
      emoji: '✨',
      message: isEditing ? 'Editing habit $habitId' : 'Create a new habit',
    );
  }
}
