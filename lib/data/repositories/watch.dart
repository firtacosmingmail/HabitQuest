import 'dart:async';

import '../models/habit.dart';

/// A stream that emits `current()` on listen and again after each [changes]
/// event. Each listener gets its own subscription (single-subscription).
Stream<T> watchValue<T>(T Function() current, Stream<void> changes) {
  late StreamController<T> controller;
  StreamSubscription<void>? sub;
  controller = StreamController<T>(
    onListen: () {
      controller.add(current());
      sub = changes.listen(
        (_) => controller.add(current()),
        onError: controller.addError,
        onDone: controller.close,
      );
    },
    onPause: () => sub?.pause(),
    onResume: () => sub?.resume(),
    onCancel: () => sub?.cancel(),
  );
  return controller.stream;
}

/// Stable ordering for habit lists: oldest first, then by id.
List<Habit> sortHabits(Iterable<Habit> habits) => habits.toList()
  ..sort((a, b) {
    final c = a.createdAt.compareTo(b.createdAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
