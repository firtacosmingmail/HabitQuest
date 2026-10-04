import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/completion_log.dart';
import '../../data/models/habit.dart';
import '../../domain/providers.dart';
import '../../domain/streaks.dart';
import '../game/ui/level_chip.dart';
import 'widgets/habit_card.dart';
import 'widgets/schedule_summary.dart';

/// Habits tab (`/habits`): greeting + today's progress, habits due today
/// with check-in buttons, other active habits and archived ones.
class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeHabitsProvider);
    final archived = ref.watch(archivedHabitsProvider);
    final due = ref.watch(dueTodayProvider);
    final log = ref.watch(completionsProvider);

    final error = active.error ?? due.error ?? log.error;
    final Widget body;
    if (error != null) {
      body = Center(child: Text('😵 Something went wrong\n$error'));
    } else if (!active.hasValue || !due.hasValue || !log.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = _HabitsList(
        active: active.requireValue,
        due: due.requireValue,
        archived: archived.value ?? const [],
        log: log.requireValue,
      );
    }

    final hasHabits = active.value?.isNotEmpty ?? false;
    return Scaffold(
      body: SafeArea(bottom: false, child: body),
      floatingActionButton: hasHabits
          ? FloatingActionButton.extended(
              key: const ValueKey('new-habit-fab'),
              onPressed: () => context.push(AppRoutes.newHabit),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New habit'),
            )
          : null,
    );
  }
}

class _HabitsList extends ConsumerWidget {
  final List<Habit> active;
  final List<Habit> due;
  final List<Habit> archived;
  final CompletionLog log;

  const _HabitsList({
    required this.active,
    required this.due,
    required this.archived,
    required this.log,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final now = ref.watch(clockProvider)();
    final dueIds = due.map((h) => h.id).toSet();
    final others = active.where((h) => !dueIds.contains(h.id)).toList();
    final done = due.where((h) => log.isCompleted(h.id, today)).length;
    // Watched here (a long-lived element) rather than in each tile, so the
    // subscriptions survive a habit moving between sections.
    final streaks = <String, StreakInfo?>{
      for (final h in [...active, ...archived])
        h.id: ref.watch(streakProvider(h.id)),
    };

    return ListView(
      padding: const EdgeInsets.only(bottom: 112),
      children: [
        _Header(
          greeting: greetingFor(now),
          done: done,
          due: due.length,
          showProgress: active.isNotEmpty,
        ),
        if (active.isEmpty)
          const HabitsEmptyState()
        else ...[
          const _SectionTitle('Today'),
          if (due.isEmpty)
            const _Note('Nothing due today. Enjoy the break 🌴')
          else
            for (final h in due)
              _HabitTile(
                habit: h,
                log: log,
                streak: streaks[h.id],
                canCheckIn: true,
              ),
          if (others.isNotEmpty) ...[
            const _SectionTitle('Other habits'),
            for (final h in others)
              _HabitTile(
                habit: h,
                log: log,
                streak: streaks[h.id],
                canCheckIn: false,
              ),
          ],
        ],
        if (archived.isNotEmpty)
          _ArchivedSection(archived: archived, log: log, streaks: streaks),
      ],
    );
  }
}

/// "Good morning", "Good afternoon" or "Good evening".
String greetingFor(DateTime now) {
  if (now.hour < 12) return 'Good morning ☀️';
  if (now.hour < 18) return 'Good afternoon 🌤️';
  return 'Good evening 🌙';
}

class _Header extends StatelessWidget {
  final String greeting;
  final int done;
  final int due;
  final bool showProgress;

  const _Header({
    required this.greeting,
    required this.done,
    required this.due,
    required this.showProgress,
  });

  String get _tagline {
    if (due == 0) return 'A free day. Rest is part of the quest.';
    if (done == due) return 'Perfect day! You crushed it 🎉';
    if (done == 0) return "Let's get the ball rolling!";
    if (done * 2 >= due) return 'Over halfway there, keep going!';
    return 'Nice start, keep it up!';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fraction = due == 0 ? 1.0 : done / due;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(greeting, style: theme.textTheme.headlineMedium),
              const LevelChip(),
            ],
          ),
          if (showProgress) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radius),
                gradient: LinearGradient(
                  colors: [scheme.primary, AppColors.sky],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Today's progress",
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '$done/$due done',
                        key: const ValueKey('today-progress'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: fraction),
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => LinearProgressIndicator(
                        value: v,
                        minHeight: 10,
                        color: AppColors.sunshine,
                        backgroundColor: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _tagline,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
}

class _Note extends StatelessWidget {
  final String text;

  const _Note(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Text(
        text,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _HabitTile extends ConsumerWidget {
  final Habit habit;
  final CompletionLog log;
  final bool canCheckIn;
  final bool dimmed;
  final StreakInfo? streak;

  const _HabitTile({
    required this.streak,
    required this.habit,
    required this.log,
    required this.canCheckIn,
    this.dimmed = false,
  });

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(habitServiceProvider)
          .toggleCompletion(habit.id, ref.read(todayProvider));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('Could not check in: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    return HabitCard(
      key: ValueKey('habit-card-${habit.id}'),
      habit: habit,
      streak: streak,
      completed: canCheckIn && log.isCompleted(habit.id, today),
      weekProgress: weeklyProgress(habit, log, today),
      showCheckIn: canCheckIn,
      checkInKey: ValueKey('checkin-${habit.id}'),
      onCheckIn: () => _toggle(context, ref),
      dimmed: dimmed,
      onTap: () => context.push(AppRoutes.habitDetails(habit.id)),
    );
  }
}

class _ArchivedSection extends StatelessWidget {
  final List<Habit> archived;
  final CompletionLog log;
  final Map<String, StreakInfo?> streaks;

  const _ArchivedSection({
    required this.archived,
    required this.log,
    required this.streaks,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const ValueKey('archived-section'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Text(
          'Archived (${archived.length})',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
        children: [
          for (final h in archived)
            _HabitTile(
              habit: h,
              log: log,
              streak: streaks[h.id],
              canCheckIn: false,
              dimmed: true,
            ),
        ],
      ),
    );
  }
}

/// Friendly empty state with a big emoji and a create button.
class HabitsEmptyState extends StatelessWidget {
  const HabitsEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 24),
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (context, s, child) =>
                Transform.scale(scale: s, child: child),
            child: const Text('🌱', style: TextStyle(fontSize: 96)),
          ),
          const SizedBox(height: 16),
          Text(
            'Your quest begins here',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Plant your first habit and watch it grow into a blazing streak.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const ValueKey('empty-create-habit'),
            onPressed: () => context.push(AppRoutes.newHabit),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create your first habit'),
          ),
        ],
      ),
    );
  }
}
