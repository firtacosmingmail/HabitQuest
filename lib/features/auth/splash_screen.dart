import 'package:flutter/material.dart';

import '../game/ui/mascot.dart';

/// Shown while the saved session is being read (usually a split second).
/// Deliberately static: no spinner flashing by.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('splash'),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MascotAvatar(title: 'Sprout', size: 96),
            const SizedBox(height: 20),
            Text('Loading your quest…', style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
