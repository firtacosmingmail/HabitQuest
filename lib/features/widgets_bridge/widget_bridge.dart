/// Keeps the home-screen widget snapshot up to date and applies check-offs
/// made on the widgets. See `docs/WIDGETS.md`.
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/dates.dart';
import '../../data/models/completion_log.dart';
import '../../domain/providers.dart';
import '../auth/auth_providers.dart';
import '../quotes/quotes_providers.dart';
import 'platform_widget_bridge.dart';
import 'widget_constants.dart';
import 'widget_snapshot.dart';
import 'widget_store.dart';
import 'widget_toggle_queue.dart';

/// The widget storage; `null` on web and desktop (the bridge is then off).
/// Tests override it with a `MemoryWidgetStore`.
final widgetStoreProvider = Provider<WidgetStore?>(
  (ref) => kIsWeb ? null : createPlatformWidgetStore(),
);

/// The bridge (`null` when there is no widget storage). Reading it wires
/// the listeners; call [WidgetBridge.start] once the platform is set up
/// (`WidgetBridgeBootstrap` does both).
final widgetBridgeProvider = Provider<WidgetBridge?>((ref) {
  final store = ref.watch(widgetStoreProvider);
  if (store == null) return null;
  final service = ref.watch(habitServiceProvider);
  final bridge = WidgetBridge(ref, store);
  // Habit data (local, remote sync, day change), quote and auth changes.
  ref.listen(dueTodayProvider, (_, _) => bridge.scheduleWrite());
  ref.listen(completionsProvider, (_, _) => bridge.scheduleWrite());
  ref.listen(todayQuoteProvider, (_, _) => bridge.scheduleWrite());
  ref.listen(authControllerProvider, (_, _) => bridge.scheduleWrite());
  final subs = [
    service.completionEvents.listen((_) => bridge.scheduleWrite()),
    service.habitChanges.listen((_) => bridge.scheduleWrite()),
    service.remoteHabitChanges.listen((_) => bridge.scheduleWrite()),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
    bridge.dispose();
  });
  return bridge;
});

/// Writes the snapshot to the [WidgetStore] and refreshes the widgets.
class WidgetBridge {
  final Ref _ref;
  final WidgetStore store;

  WidgetBridge(this._ref, this.store);

  bool _started = false;
  bool _disposed = false;
  bool _writeScheduled = false;
  Timer? _midnight;
  WidgetSnapshot? _last;
  String? _day;
  Future<void> _chain = Future.value();
  Future<int>? _applying;

  bool get isStarted => _started;

  /// The snapshot last written by this bridge.
  WidgetSnapshot? get lastSnapshot => _last;

  DateTime _now() => _ref.read(clockProvider)();

  /// Applies queued widget check-offs, writes the snapshot and arms the
  /// midnight timer. Call after the platform setup (App Group).
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _day = dateKey(_now());
    _armMidnight();
    await applyQueue();
  }

  /// App resumed: roll the day over if needed, apply queued check-offs and
  /// rewrite the snapshot.
  Future<void> onResume() async {
    if (!_started || _disposed) return;
    _checkDayChange();
    _armMidnight();
    await applyQueue();
  }

  /// Applies the check-offs queued by the widgets' background callback,
  /// then rewrites the snapshot (forced: the widget may show an optimistic
  /// flip). Concurrent calls share one run. Returns the check-ins changed.
  Future<int> applyQueue() {
    if (!_started || _disposed) return Future.value(0);
    return _applying ??= _applyQueue().whenComplete(() => _applying = null);
  }

  Future<int> _applyQueue() async {
    var changed = 0;
    try {
      changed = await applyPendingToggles(
        store,
        _ref.read(habitServiceProvider),
      );
    } on Object catch (e) {
      developer.log('Applying widget check-offs failed: $e',
          name: 'WidgetBridge');
    }
    await writeNow(force: true);
    return changed;
  }

  /// Coalesces bursts of changes into one write (next microtask).
  void scheduleWrite() {
    if (!_started || _disposed || _writeScheduled) return;
    _writeScheduled = true;
    scheduleMicrotask(() {
      _writeScheduled = false;
      _checkDayChange();
      unawaited(writeNow());
    });
  }

  /// Builds and stores the snapshot and refreshes the widgets, unless the
  /// content did not change (or [force]). Skipped while auth or the habits
  /// are still loading. Writes are serialised.
  Future<void> writeNow({bool force = false}) {
    final next = _chain.then((_) => _write(force));
    _chain = next.catchError((Object e) {
      developer.log('Widget snapshot write failed: $e', name: 'WidgetBridge');
    });
    return _chain;
  }

  Future<void> _write(bool force) async {
    if (_disposed) return;
    final snapshot = buildCurrentSnapshot();
    if (snapshot == null) return;
    if (!force && _last != null && _last!.sameContentAs(snapshot)) return;
    _last = snapshot;
    await store.write(WidgetConstants.snapshotKey, snapshot.encode());
    await store.refreshWidgets();
  }

  /// The snapshot for the current app state, or `null` while loading.
  WidgetSnapshot? buildCurrentSnapshot() {
    final auth = _ref.read(authControllerProvider);
    if (auth is AuthUnknown) return null;
    final signedIn = auth is SignedIn;
    final due = _ref.read(dueTodayProvider);
    if (signedIn && !due.hasValue) return null;
    final quote = _ref.read(todayQuoteProvider).value?.quote;
    return buildWidgetSnapshot(
      signedIn: signedIn,
      today: _ref.read(todayProvider),
      dueToday: due.value ?? const [],
      log: _ref.read(completionsProvider).value ?? const CompletionLog.empty(),
      quote: signedIn ? quote : null,
      now: _now(),
    );
  }

  /// Rolls `todayProvider` over when the local day changed since the last
  /// check (the providers then rebuild and the snapshot is rewritten).
  void _checkDayChange() {
    final day = dateKey(_now());
    if (day == _day) return;
    _day = day;
    _ref.invalidate(todayProvider);
    scheduleWrite();
  }

  void _armMidnight() {
    _midnight?.cancel();
    final now = _now();
    final next = addDays(dateOnly(now), 1);
    // A little after midnight, so the clock is surely on the new day.
    final delay = next.difference(now) + const Duration(seconds: 1);
    _midnight = Timer(delay, onMidnight);
  }

  /// The midnight timer fired: new day, new snapshot.
  @visibleForTesting
  void onMidnight() {
    if (_disposed) return;
    _checkDayChange();
    unawaited(writeNow(force: true));
    _armMidnight();
  }

  void dispose() {
    _disposed = true;
    _midnight?.cancel();
  }
}

/// Check-offs from a widget URI that *opened* the app (e.g. iOS < 17,
/// where the check button is a deep link). Toggles today's check-in once;
/// the same habit again within [dedupeWindow] is ignored, in case the
/// platform delivers the link twice.
final widgetLinkHandlerProvider = Provider<WidgetLinkHandler>(
  WidgetLinkHandler.new,
);

class WidgetLinkHandler {
  final Ref _ref;
  final _recent = <String, DateTime>{};

  static const dedupeWindow = Duration(seconds: 3);

  WidgetLinkHandler(this._ref);

  /// Returns the new state (`true` = done), or `null` when ignored.
  Future<bool?> toggle(String habitId) async {
    final now = _ref.read(clockProvider)();
    final last = _recent[habitId];
    if (last != null && now.difference(last).abs() < dedupeWindow) {
      return null;
    }
    _recent[habitId] = now;
    final service = _ref.read(habitServiceProvider);
    if (service.repository.getHabit(habitId) == null) return null;
    try {
      return await service.toggleCompletion(habitId, service.today);
    } on Object catch (e) {
      developer.log('Widget link check-off failed: $e', name: 'WidgetBridge');
      return null;
    }
  }
}
