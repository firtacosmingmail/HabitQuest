/// Check-offs from a home-screen widget.
///
/// The widget's background callback runs in a separate isolate (a headless
/// Flutter engine) that must not open the app's hive boxes: hive is not
/// multi-isolate safe, and the running app would keep its in-memory copy
/// anyway. So the callback only [recordWidgetToggle]s: it queues the wanted
/// state in the widget storage and flips `done` in the snapshot so the
/// widget updates at once. The app then [applyPendingToggles] through
/// `HabitService.setCompletion` (the call behind `toggleCompletion`), so XP,
/// streaks, reminders and sync behave exactly as for an in-app check-off.
/// See `docs/WIDGETS.md` ("Check-off from a widget").
library;

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import '../../core/utils/dates.dart';
import '../../domain/habit_service.dart';
import 'widget_constants.dart';
import 'widget_links.dart';
import 'widget_snapshot.dart';
import 'widget_store.dart';

/// One queued check-off: set [habitId] on [date] to [done].
///
/// It records the *wanted state*, not a flip, so applying it twice (or
/// after the app already did the same) changes nothing.
class PendingToggle {
  final String id;
  final String habitId;

  /// `yyyy-MM-dd` (local day).
  final String date;
  final bool done;

  /// When the widget was tapped (UTC).
  final DateTime at;

  const PendingToggle({
    required this.id,
    required this.habitId,
    required this.date,
    required this.done,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'habitId': habitId,
        'date': date,
        'done': done,
        'at': at.toUtc().toIso8601String(),
      };

  factory PendingToggle.fromJson(Map<String, dynamic> json) => PendingToggle(
        id: json['id'] as String,
        habitId: json['habitId'] as String,
        date: json['date'] as String,
        done: json['done'] as bool,
        at: DateTime.parse(json['at'] as String),
      );
}

/// Reads the queue (unreadable entries are dropped).
Future<List<PendingToggle>> readToggleQueue(WidgetStore store) async {
  final raw = await store.read(WidgetConstants.toggleQueueKey);
  if (raw == null || raw.isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List;
    final out = <PendingToggle>[];
    for (final e in list) {
      try {
        out.add(PendingToggle.fromJson(Map<String, dynamic>.from(e as Map)));
      } on Object {
        // Skip a malformed entry.
      }
    }
    return out;
  } on Object {
    return [];
  }
}

Future<void> _writeQueue(WidgetStore store, List<PendingToggle> queue) =>
    store.write(
      WidgetConstants.toggleQueueKey,
      queue.isEmpty ? null : jsonEncode([for (final t in queue) t.toJson()]),
    );

String _randomId() {
  final r = Random();
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${r.nextInt(1 << 32).toRadixString(36)}';
}

/// Background side: records a check-off of [habitId] tapped on the widget.
///
/// Flips the habit's `done` in the stored snapshot, queues that wanted
/// state and refreshes the widgets. If the snapshot is from an earlier day
/// (the app has not run since midnight), it is rolled over to today first
/// with every habit not done. Returns the queued toggle, or `null` when
/// there is nothing to toggle (no snapshot, not `ok`, unknown habit).
Future<PendingToggle?> recordWidgetToggle(
  WidgetStore store,
  String habitId, {
  required DateTime now,
  String Function()? newId,
}) async {
  var snapshot = WidgetSnapshot.tryDecode(
    await store.read(WidgetConstants.snapshotKey),
  );
  if (snapshot == null || snapshot.state != WidgetSnapshotState.ok) {
    return null;
  }
  final todayKey = dateKey(now);
  if (snapshot.date != todayKey) {
    snapshot = snapshot.copyWith(
      date: todayKey,
      habits: [for (final h in snapshot.habits) h.copyWith(done: false)],
    );
  }
  final index = snapshot.habits.indexWhere((h) => h.id == habitId);
  if (index < 0) return null;
  final done = !snapshot.habits[index].done;
  final toggle = PendingToggle(
    id: (newId ?? _randomId)(),
    habitId: habitId,
    date: todayKey,
    done: done,
    at: now.toUtc(),
  );
  final habits = [...snapshot.habits];
  habits[index] = habits[index].copyWith(done: done);
  await _writeQueue(store, [...await readToggleQueue(store), toggle]);
  await store.write(
    WidgetConstants.snapshotKey,
    snapshot.copyWith(habits: habits, generatedAt: now.toUtc()).encode(),
  );
  await store.refreshWidgets();
  return toggle;
}

/// App side: applies every queued check-off through [service], oldest
/// first, collapsed to the last wanted state per habit and day, then
/// removes exactly the applied entries (toggles queued meanwhile stay).
///
/// Idempotent: entries carry the wanted state and `setCompletion` is a
/// no-op when the habit already has it. Toggles for unknown (deleted)
/// habits or future days are dropped. Returns how many check-ins changed.
Future<int> applyPendingToggles(WidgetStore store, HabitService service) async {
  final queue = await readToggleQueue(store);
  if (queue.isEmpty) return 0;
  final wanted = <String, PendingToggle>{};
  for (final t in queue) {
    wanted.remove('${t.habitId}|${t.date}');
    wanted['${t.habitId}|${t.date}'] = t;
  }
  final handled = <String>{for (final t in queue) t.id};
  var changed = 0;
  for (final t in wanted.values) {
    try {
      final date = parseDateKey(t.date);
      if (service.repository.getHabit(t.habitId) == null) continue;
      if (dateOnly(date).isAfter(service.today)) continue;
      if (service.isCompleted(t.habitId, date) == t.done) continue;
      await service.setCompletion(t.habitId, date, t.done);
      changed++;
    } on FormatException {
      // Bad date: drop it.
    } on Object catch (e) {
      // Unexpected (e.g. storage): keep this day's entries for next time.
      developer.log('Widget toggle not applied: $e', name: 'WidgetBridge');
      handled.removeWhere(
        (id) => queue.any(
          (q) => q.id == id && q.habitId == t.habitId && q.date == t.date,
        ),
      );
    }
  }
  final latest = await readToggleQueue(store);
  await _writeQueue(store, [
    for (final t in latest)
      if (!handled.contains(t.id)) t,
  ]);
  return changed;
}

/// Background callback body: records the check-off carried by [uri]
/// (`habitquest://widget/toggle?habitId=`); ignores any other URI.
Future<PendingToggle?> handleWidgetInteraction(
  Uri? uri,
  WidgetStore store, {
  required DateTime now,
}) async {
  final habitId = toggleHabitId(uri);
  if (habitId == null) return null;
  return recordWidgetToggle(store, habitId, now: now);
}
