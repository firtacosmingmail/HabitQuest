import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../game_providers.dart';

/// Compact "Lv 3 · Seeker" chip with a mini XP progress ring. Tapping it
/// opens the Quest tab.
class LevelChip extends ConsumerWidget {
  const LevelChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(gameProfileProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label:
          'Level ${profile.level} ${profile.title}, '
          '${profile.xpIntoLevel} of ${profile.xpForNextLevel} XP',
      child: Material(
        color: scheme.primaryContainer,
        shape: const StadiumBorder(),
        child: InkWell(
          key: const ValueKey('level-chip'),
          customBorder: const StadiumBorder(),
          onTap: () => context.go(AppRoutes.quest),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: profile.progress),
                        duration: const Duration(milliseconds: 500),
                        builder: (context, v, _) => CircularProgressIndicator(
                          value: v,
                          strokeWidth: 3,
                          color: AppColors.sunshine,
                          backgroundColor: scheme.surface,
                        ),
                      ),
                      const Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: AppColors.sunshine,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                ExcludeSemantics(
                  child: Text(
                    'Lv ${profile.level} · ${profile.title}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
