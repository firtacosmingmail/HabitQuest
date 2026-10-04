import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/game/game_providers.dart';
import 'features/game/ui/game_celebrations.dart';

/// Root widget. Expects a [ProviderScope] above it that overrides
/// `habitRepositoryProvider`.
class HabitQuestApp extends ConsumerWidget {
  const HabitQuestApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Start the game engine at launch so it hears every check-in.
    ref.watch(gameEngineProvider);
    return MaterialApp.router(
      title: 'Habit Quest',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
      // App-wide game celebrations (+XP, level-up, achievement toasts).
      builder: (context, child) =>
          GameCelebrations(child: child ?? const SizedBox.shrink()),
    );
  }
}
