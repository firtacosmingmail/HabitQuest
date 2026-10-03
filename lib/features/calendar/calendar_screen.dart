import 'package:flutter/material.dart';

import '../../core/widgets/placeholder_screen.dart';

/// Calendar tab (`/calendar`). Placeholder: built by the calendar task.
class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Calendar',
      emoji: '📅',
      message: 'Your month of quests is coming soon.',
    );
  }
}
