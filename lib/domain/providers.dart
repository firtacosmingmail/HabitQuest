/// Riverpod providers for the data + domain layers.
///
/// The app overrides [habitRepositoryProvider] in `main.dart` with a
/// `HiveHabitRepository`; tests override it with `InMemoryHabitRepository`
/// (and optionally [clockProvider] with a fixed clock).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/dates.dart';
import '../data/models/completion_log.dart';
import '../data/models/habit.dart';
import '../data/repositories/habit_repository.dart';
import 'habit_events.dart';
import 'habit_service.dart';
import 'recurrence.dart';
import 'streaks.dart';

/// Storage. Must be overridden (see `main.dart` / tests).
final habitRepositoryProvider = Provider<HabitRepository>(
  (ref) => throw UnimplementedError(
    'habitRepositoryProvider must be overridden in ProviderScope',
  ),
);

/// Source of "now". Override in tests for deterministic dates.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Today's date (local midnight). The app shell invalidates this when the
/// app is resumed so it rolls over after midnight.
final todayProvider = Provider<DateTime>((ref) => today(ref.watch(clockProvider)));

/// The single [HabitService]; use it for every mutation.
final habitServiceProvider = Provider<HabitService>((ref) {
  final service = HabitService(
    ref.watch(habitRepositoryProvider),
    now: ref.watch(clockProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// All habits, including archived ones, sorted by creation.
final habitsProvider = StreamProvider<List<Habit>>(
  (ref) => ref.watch(habitRepositoryProvider).watchHabits(),
);

/// Non-archived habits.
final activeHabitsProvider = Provider<AsyncValue<List<Habit>>>(
  (ref) => ref
      .watch(habitsProvider)
      .whenData((all) => all.where((h) => !h.archived).toList()),
);

/// Archived habits.
final archivedHabitsProvider = Provider<AsyncValue<List<Habit>>>(
  (ref) => ref
      .watch(habitsProvider)
      .whenData((all) => all.where((h) => h.archived).toList()),
);

/// A single habit by id (`null` once deleted / if unknown).
final habitByIdProvider = Provider.family<AsyncValue<Habit?>, String>(
  (ref, id) => ref.watch(habitsProvider).whenData(
        (all) => all.where((h) => h.id == id).firstOrNull,
      ),
);

/// All check-ins.
final completionsProvider = StreamProvider<CompletionLog>(
  (ref) => ref.watch(habitRepositoryProvider).watchCompletions(),
);

/// Non-archived habits due on a date (pass a `dateOnly` value as the key).
final dueHabitsProvider = Provider.family<AsyncValue<List<Habit>>, DateTime>(
  (ref, date) {
    final habits = ref.watch(habitsProvider);
    final log = ref.watch(completionsProvider);
    return _combine(habits, log, (h, c) => dueHabitsOn(h, date, c));
  },
);

/// Habits due today.
final dueTodayProvider = Provider<AsyncValue<List<Habit>>>(
  (ref) => ref.watch(dueHabitsProvider(ref.watch(todayProvider))),
);

/// Current/best streak of a habit as of today (`null` if the habit is
/// unknown or data is still loading).
final streakProvider = Provider.family<StreakInfo?, String>((ref, habitId) {
  final habit = ref.watch(habitByIdProvider(habitId)).value;
  final log = ref.watch(completionsProvider).value;
  if (habit == null || log == null) return null;
  return streakInfo(habit, log, ref.watch(todayProvider));
});

/// Whether a date was a Perfect Day (pass a `dateOnly` value as the key).
final isPerfectDayProvider = Provider.family<bool, DateTime>((ref, date) {
  final habits = ref.watch(habitsProvider).value;
  final log = ref.watch(completionsProvider).value;
  if (habits == null || log == null) return false;
  return isPerfectDay(date, habits, log);
});

/// Check-in events (convenience; equivalent to
/// `ref.read(habitServiceProvider).completionEvents`).
final completionEventsProvider = Provider<Stream<CompletionEvent>>(
  (ref) => ref.watch(habitServiceProvider).completionEvents,
);

/// Habit lifecycle events (convenience; equivalent to
/// `ref.read(habitServiceProvider).habitChanges`).
final habitChangesProvider = Provider<Stream<HabitChangeEvent>>(
  (ref) => ref.watch(habitServiceProvider).habitChanges,
);

AsyncValue<R> _combine<A, B, R>(
  AsyncValue<A> a,
  AsyncValue<B> b,
  R Function(A, B) combine,
) {
  if (a.hasError) return AsyncValue.error(a.error!, a.stackTrace!);
  if (b.hasError) return AsyncValue.error(b.error!, b.stackTrace!);
  final va = a.value;
  final vb = b.value;
  if (va == null || vb == null) return const AsyncValue.loading();
  return AsyncValue.data(combine(va, vb));
}
