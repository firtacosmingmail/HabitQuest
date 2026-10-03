import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../../core/widgets/placeholder_screen.dart';

/// Habits tab (`/habits`). Placeholder: built by the habits-screen task.
class HabitsScreen extends StatelessWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PlaceholderScreen(
      title: 'Habits',
      emoji: '🌱',
      message: 'Your habits will live here.',
      actions: [
        FilledButton.icon(
          onPressed: () => context.push(AppRoutes.newHabit),
          icon: const Icon(Icons.add),
          label: const Text('New habit'),
        ),
      ],
    );
  }
}
