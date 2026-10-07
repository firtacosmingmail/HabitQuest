import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_providers.dart';
import '../game/achievements.dart';
import '../game/game_profile.dart';
import '../game/game_providers.dart';
import '../game/game_rules.dart';
import '../game/ui/mascot.dart';
import '../sync/ui/sync_status_indicator.dart';

/// Quest tab (`/quest`): hero card (mascot, level, title, XP bar), stats,
/// achievements grid and a "How to earn XP" explainer.
class QuestScreen extends ConsumerWidget {
  const QuestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(gameProfileProvider);
    final catalog = ref.watch(achievementsCatalogProvider);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Your quest',
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  key: const ValueKey('logout-button'),
                  tooltip: 'Log out',
                  icon: const Icon(Icons.logout_rounded),
                  onPressed: () => confirmAndLogout(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 12),
            HeroCard(profile: profile),
            const SizedBox(height: 16),
            _StatsRow(stats: profile.stats),
            const SizedBox(height: 16),
            const SyncNowCard(),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Achievements',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Text(
                  '${profile.unlockedAchievements.length}/${catalog.length}',
                  key: const ValueKey('achievements-count'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _AchievementsGrid(catalog: catalog, profile: profile),
            const SizedBox(height: 24),
            const _HowToEarnCard(),
          ],
        ),
      ),
    );
  }
}

/// Asks for confirmation, then logs out (the auth gate then shows /login).
/// Local habit data stays on the device.
Future<void> confirmAndLogout(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('logout-dialog'),
      icon: const Text('👋', style: TextStyle(fontSize: 40)),
      title: const Text('Leaving the quest?'),
      content: const Text(
        'You will be logged out. Your habits stay on this device.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Stay'),
        ),
        FilledButton(
          key: const ValueKey('confirm-logout'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Log out'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(authControllerProvider.notifier).logout();
}

/// Mascot, level, title and the animated XP bar.
class HeroCard extends StatelessWidget {
  final GameProfile profile;

  const HeroCard({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final accent = colorForTitle(profile.title);
    const white = Colors.white;
    return Container(
      key: const ValueKey('hero-card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radius * 1.25),
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MascotAvatar(title: profile.title, size: 84),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Level ${profile.level}',
                      key: const ValueKey('hero-level'),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      profile.title,
                      key: const ValueKey('hero-title'),
                      style: theme.textTheme.titleLarge?.copyWith(color: white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${profile.xp} XP total',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween(
                begin: reduce ? profile.progress : 0,
                end: profile.progress,
              ),
              duration: reduce
                  ? Duration.zero
                  : const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                key: const ValueKey('xp-bar'),
                value: v,
                minHeight: 14,
                color: AppColors.sunshine,
                backgroundColor: white.withValues(alpha: 0.3),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${profile.xpIntoLevel} / ${profile.xpForNextLevel} XP',
                  key: const ValueKey('hero-xp'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                'Next: Lv ${profile.level + 1}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final GameStats stats;

  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _StatTile(
          key: const ValueKey('stat-check-ins'),
          emoji: '✅',
          value: '${stats.totalCheckIns}',
          label: 'Check-ins',
          accent: AppColors.mint,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _StatTile(
          key: const ValueKey('stat-best-streak'),
          emoji: '🔥',
          value: '${stats.bestStreakEver}',
          label: 'Best streak',
          accent: AppColors.flame,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _StatTile(
          key: const ValueKey('stat-perfect-days'),
          emoji: '🌟',
          value: '${stats.perfectDays}',
          label: 'Perfect Days',
          accent: AppColors.perfectDay,
        ),
      ),
    ],
  );
}

class _StatTile extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final Color accent;

  const _StatTile({
    super.key,
    required this.emoji,
    required this.value,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: accent.withValues(alpha: 0.4), width: 2),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementsGrid extends StatelessWidget {
  final List<Achievement> catalog;
  final GameProfile profile;

  const _AchievementsGrid({required this.catalog, required this.profile});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 120).floor().clamp(3, 6);
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.68,
          children: [
            for (final a in catalog)
              AchievementBadge(
                achievement: a,
                unlockedAt: profile.unlockedAt(a.id),
              ),
          ],
        );
      },
    );
  }
}

const _greyscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 0.45, 0,
]);

/// A badge tile: colourful with its unlock date, or greyed out and locked.
/// Tapping it shows the details in a bottom sheet.
class AchievementBadge extends StatelessWidget {
  final Achievement achievement;
  final DateTime? unlockedAt;

  const AchievementBadge({
    super.key,
    required this.achievement,
    required this.unlockedAt,
  });

  bool get unlocked => unlockedAt != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: '${achievement.name}, ${unlocked ? 'unlocked' : 'locked'}',
      excludeSemantics: true,
      child: Material(
        color: unlocked
            ? AppColors.sunshine.withValues(alpha: 0.18)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: InkWell(
          key: ValueKey(
            '${unlocked ? 'badge-unlocked' : 'badge-locked'}-${achievement.id}',
          ),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          onTap: () => showAchievementSheet(context, achievement, unlockedAt),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    unlocked
                        ? Text(
                            achievement.emoji,
                            style: const TextStyle(fontSize: 34),
                          )
                        : ColorFiltered(
                            colorFilter: _greyscale,
                            child: Text(
                              achievement.emoji,
                              style: const TextStyle(fontSize: 34),
                            ),
                          ),
                    if (!unlocked)
                      Positioned(
                        right: -8,
                        bottom: -4,
                        child: Icon(
                          Icons.lock_rounded,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  achievement.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: unlocked ? null : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  unlocked
                      ? DateFormat.yMMMd().format(unlockedAt!)
                      : achievement.hint,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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

/// Bottom sheet with an achievement's details.
Future<void> showAchievementSheet(
  BuildContext context,
  Achievement achievement,
  DateTime? unlockedAt,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      final unlocked = unlockedAt != null;
      return SafeArea(
        child: Padding(
          key: const ValueKey('achievement-sheet'),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: unlocked ? 1 : 0.45,
                child: Text(
                  achievement.emoji,
                  style: const TextStyle(fontSize: 64),
                ),
              ),
              const SizedBox(height: 8),
              Text(achievement.name, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                unlocked ? achievement.description : achievement.hint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              Chip(
                avatar: Icon(
                  unlocked ? Icons.check_circle_rounded : Icons.lock_rounded,
                  size: 18,
                ),
                label: Text(
                  unlocked
                      ? 'Unlocked ${DateFormat.yMMMd().format(unlockedAt)}'
                      : 'Locked',
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _HowToEarnCard extends StatelessWidget {
  const _HowToEarnCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget row(String emoji, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
    return Container(
      key: const ValueKey('how-to-earn'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: AppColors.sunshine.withValues(alpha: 0.6),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How to earn XP', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          row('✅', '${GameRules.checkInXp} XP for every check-in'),
          row(
            '🔥',
            '+1 XP per streak period, up to +${GameRules.maxStreakBonus}',
          ),
          row(
            '🌟',
            '+${GameRules.perfectDayXp} XP for a Perfect Day '
                '(every habit due that day done)',
          ),
          row('⬆️', 'Level n → n+1 costs 100 × n XP'),
        ],
      ),
    );
  }
}
