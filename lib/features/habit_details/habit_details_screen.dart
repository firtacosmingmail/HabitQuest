import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/completion_log.dart';
import '../../data/models/habit.dart';
import '../../domain/providers.dart';
import '../../domain/streaks.dart';
import '../ads/ad_placement.dart';
import '../ads/ad_slot.dart';
import 'completion_rate.dart';
import 'widgets/habit_header.dart';
import 'widgets/habit_month_calendar.dart';
import 'widgets/stat_tile.dart';
import 'widgets/streak_flame.dart';

/// Habit details (`/habits/:id`): header, streak/stat tiles, a monthly
/// check-in heatmap (tap past days to toggle) and edit/archive/delete.
class HabitDetailsScreen extends ConsumerWidget {
  final String habitId;

  const HabitDetailsScreen({super.key, required this.habitId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitAsync = ref.watch(habitByIdProvider(habitId));
    final logAsync = ref.watch(completionsProvider);
    final today = ref.watch(todayProvider);

    if (habitAsync.hasError || logAsync.hasError) {
      return const _MessageScaffold(
        emoji: '😵',
        title: 'Something went wrong',
        message: 'This habit could not be loaded.',
      );
    }
    final log = logAsync.value;
    if (!habitAsync.hasValue || log == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final habit = habitAsync.value;
    if (habit == null) {
      return const _MessageScaffold(
        key: ValueKey('habit-not-found'),
        emoji: '🕵️',
        title: 'Habit not found',
        message: 'This habit may have been deleted.\n'
            'Let’s head back to your quests!',
      );
    }
    return _HabitDetailsBody(habit: habit, log: log, today: today);
  }
}

class _HabitDetailsBody extends ConsumerWidget {
  final Habit habit;
  final CompletionLog log;
  final DateTime today;

  const _HabitDetailsBody({
    required this.habit,
    required this.log,
    required this.today,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final streak = streakInfo(habit, log, today);
    final rate = completionRate(habit, log, today);
    final total = log.totalFor(habit.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Habit'),
        actions: [
          IconButton(
            key: const ValueKey('habit-edit'),
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => context.push(AppRoutes.editHabit(habit.id)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            HabitHeader(habit: habit),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    key: const ValueKey('stat-current-streak'),
                    accent: AppColors.flame,
                    visual: StreakFlame(streak: streak.current),
                    value: _periods(streak.current, streak.unit),
                    label: 'Current streak',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatTile(
                    key: const ValueKey('stat-best-streak'),
                    accent: AppColors.sunshine,
                    visual: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        StreakFlame(streak: streak.best),
                        const Text('👑', style: TextStyle(fontSize: 16)),
                      ],
                    ),
                    value: _periods(streak.best, streak.unit),
                    label: 'Best streak',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    key: const ValueKey('stat-total'),
                    accent: AppColors.mint,
                    visual: const Icon(
                      Icons.check_circle_rounded,
                      size: 40,
                      color: AppColors.mint,
                    ),
                    value: '$total',
                    label: 'Total check-ins',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatTile(
                    key: const ValueKey('stat-rate'),
                    accent: AppColors.sky,
                    visual: _RateRing(ratio: rate.ratio),
                    value: rate.percent == null ? '—' : '${rate.percent}%',
                    label: 'Completion rate',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Check-ins', style: theme.textTheme.titleLarge),
            ),
            HabitMonthCalendar(
              habit: habit,
              completions: log,
              today: today,
              onToggle: (date) => _toggle(context, ref, date),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Text(
                'Tap a day to check in or undo.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const AdSlot(
              key: ValueKey('details-ad'),
              placement: AdPlacement.habitDetails,
            ),
            const SizedBox(height: 16),
            _Actions(habit: habit),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, DateTime date) async {
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(habitServiceProvider).toggleCompletion(habit.id, date);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }
}

String _periods(int n, StreakUnit unit) => switch (unit) {
      StreakUnit.days => n == 1 ? '1 day' : '$n days',
      StreakUnit.weeks => n == 1 ? '1 week' : '$n weeks',
    };

class _RateRing extends StatelessWidget {
  final double? ratio;

  const _RateRing({required this.ratio});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 38,
      height: 38,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: ratio ?? 0),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => CircularProgressIndicator(
          value: value,
          strokeWidth: 7,
          strokeCap: StrokeCap.round,
          backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
          color: AppColors.sky,
        ),
      ),
    );
  }
}

class _Actions extends ConsumerWidget {
  final Habit habit;

  const _Actions({required this.habit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const ValueKey('habit-edit-button'),
          onPressed: () => context.push(AppRoutes.editHabit(habit.id)),
          icon: const Icon(Icons.edit_rounded),
          label: const Text('Edit habit'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('habit-archive'),
                onPressed: () => _toggleArchive(context, ref),
                icon: Icon(habit.archived
                    ? Icons.unarchive_rounded
                    : Icons.archive_rounded),
                label: Text(habit.archived ? 'Unarchive' : 'Archive'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('habit-delete'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.error,
                  side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
                ),
                onPressed: () => _delete(context, ref),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _toggleArchive(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final archive = !habit.archived;
    await ref
        .read(habitServiceProvider)
        .archiveHabit(habit.id, archived: archive);
    messenger.showSnackBar(SnackBar(
      content: Text(archive
          ? '${habit.emoji} ${habit.name} archived'
          : '${habit.emoji} ${habit.name} is back in action!'),
    ));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Text(habit.emoji, style: const TextStyle(fontSize: 40)),
        title: Text('Delete “${habit.name}”?'),
        content: const Text(
          'All of its check-ins and streaks will be gone for good.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('delete-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            key: const ValueKey('delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final service = ref.read(habitServiceProvider);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await service.deleteHabit(habit.id);
    router.go(AppRoutes.habits);
    messenger.showSnackBar(
      SnackBar(content: Text('${habit.emoji} ${habit.name} deleted')),
    );
  }
}

class _MessageScaffold extends StatelessWidget {
  final String emoji;
  final String title;
  final String message;

  const _MessageScaffold({
    super.key,
    required this.emoji,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 72)),
              const SizedBox(height: 16),
              Text(title,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(message,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const ValueKey('back-to-habits'),
                onPressed: () => context.go(AppRoutes.habits),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back to habits'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
