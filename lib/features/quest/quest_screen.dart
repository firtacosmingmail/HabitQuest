import 'package:flutter/material.dart';

import '../../core/widgets/placeholder_screen.dart';

/// Quest tab (`/quest`): profile, level, achievements. Placeholder: built by
/// the game UI task.
class QuestScreen extends StatelessWidget {
  const QuestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Quest',
      emoji: '🏆',
      message: 'Levels and achievements are on their way.',
    );
  }
}
