import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/remote/api_exception.dart';
import '../../domain/providers.dart';
import '../auth/auth_providers.dart';
import 'sync_engine.dart';
import 'sync_providers.dart';

enum SyncPhase {
  /// Sync not started yet / nothing happened yet this run.
  idle,

  /// Signed out: nothing syncs.
  signedOut,
  syncing,
  synced,

  /// The backend cannot be reached; changes wait in the queue.
  offline,

  /// The last run failed (will retry) or some changes were refused.
  error,
}

/// What the sync indicator shows.
class SyncStatus {
  final SyncPhase phase;
  final DateTime? lastSyncedAt;

  /// Local changes waiting to be pushed.
  final int pending;

  /// Human-readable detail for [SyncPhase.error].
  final String? message;

  /// Changes the server refused (kept in the queue).
  final List<SyncIssue> issues;

  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.lastSyncedAt,
    this.pending = 0,
    this.message,
    this.issues = const [],
  });

  SyncStatus copyWith({
    SyncPhase? phase,
    DateTime? lastSyncedAt,
    int? pending,
    String? Function()? message,
    List<SyncIssue>? issues,
  }) =>
      SyncStatus(
        phase: phase ?? this.phase,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        pending: pending ?? this.pending,
        message: message != null ? message() : this.message,
        issues: issues ?? this.issues,
      );

  @override
  String toString() => 'SyncStatus(${phase.name}, pending: $pending, '
      'last: $lastSyncedAt, issues: ${issues.length})';
}

/// Decides *when* to sync and exposes the [SyncStatus].
///
/// Triggers (once [start]ed, see `SyncBootstrap`): app start when signed in
/// and login ([onAuthChanged]), regaining connectivity, app resume
/// ([onAppResumed]), local changes (debounced by [debounce]) and [syncNow].
/// Never syncs while signed out. Runs are serialised; a trigger during a
/// run schedules one more run afterwards. Transient failures retry with
/// exponential backoff ([minBackoff] doubling up to [maxBackoff]).
class SyncController extends Notifier<SyncStatus> {
  static const debounce = Duration(seconds: 3);
  static const minBackoff = Duration(seconds: 5);
  static const maxBackoff = Duration(minutes: 5);

  Timer? _debounceTimer;
  Timer? _retryTimer;
  final List<StreamSubscription<Object?>> _subs = [];
  int _failures = 0;
  bool _started = false;
  bool _again = false;
  Future<void>? _running;

  /// Set by a `429 rate_limited`: automatic triggers (local changes,
  /// connectivity, resume) wait for the backoff retry instead of hammering
  /// the server. Only [syncNow] overrides it.
  bool _rateLimited = false;

  @override
  SyncStatus build() {
    ref.onDispose(_stop);
    final queue = ref.watch(syncQueueProvider);
    final user = _userId;
    return SyncStatus(
      phase: user == null ? SyncPhase.signedOut : SyncPhase.idle,
      pending: queue.length,
      lastSyncedAt: user == null
          ? null
          : ref.watch(syncMetaProvider).lastSyncedAt(user)?.toLocal(),
    );
  }

  String? get _userId => switch (ref.read(authControllerProvider)) {
        SignedIn(:final session) => session.user.id,
        _ => null,
      };

  DateTime _now() => ref.read(clockProvider)();

  /// Starts listening to connectivity and local changes, and syncs now if
  /// signed in. Idempotent.
  void start() {
    if (_started) return;
    _started = true;
    final queue = ref.read(syncQueueProvider);
    _subs
      ..add(queue.changes.listen((_) {
        _setPending();
        _schedule(debounce);
      }))
      ..add(ref.read(connectivityMonitorProvider).changes.listen((online) {
        if (online) {
          if (!_rateLimited) _failures = 0;
          _schedule(Duration.zero);
        } else if (_userId != null) {
          state = state.copyWith(phase: SyncPhase.offline);
        }
      }));
    if (_userId != null) _schedule(Duration.zero);
  }

  /// Call with every auth state (login, logout, restored session).
  void onAuthChanged(AuthState auth) {
    if (auth is SignedIn) {
      if (_started) {
        if (!_rateLimited) _failures = 0;
        _schedule(Duration.zero);
      }
    } else if (auth is SignedOut) {
      _cancelTimers();
      state = SyncStatus(
        phase: SyncPhase.signedOut,
        pending: ref.read(syncQueueProvider).length,
      );
    }
  }

  void onAppResumed() {
    if (_started && _userId != null) _schedule(Duration.zero);
  }

  /// Manual "Sync now": runs immediately (resets the backoff).
  Future<void> syncNow() {
    _failures = 0;
    _rateLimited = false;
    _cancelTimers();
    return _run();
  }

  void _schedule(Duration delay) {
    // While rate limited the pending backoff retry does the next run.
    if (_rateLimited) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () => unawaited(_run()));
  }

  Future<void> _run() async {
    if (_running != null) {
      _again = true;
      return _running;
    }
    final done = Completer<void>();
    _running = done.future;
    try {
      await _runOnce();
    } finally {
      _running = null;
      done.complete();
    }
    if (_again && ref.mounted) {
      _again = false;
      await _run();
    }
  }

  Future<void> _runOnce() async {
    final user = _userId;
    if (user == null) {
      state = state.copyWith(phase: SyncPhase.signedOut);
      return;
    }
    final online = await ref.read(connectivityMonitorProvider).isOnline();
    if (!ref.mounted) return;
    if (!online) {
      state = state.copyWith(phase: SyncPhase.offline);
      _setPending();
      _scheduleRetry();
      return;
    }
    state = state.copyWith(phase: SyncPhase.syncing);
    final engine = ref.read(syncEngineProvider);
    try {
      final change = await engine.prepareForUser(user);
      if (change != AccountChange.none) {
        developer.log('Account change: ${change.name}', name: 'Sync');
      }
      final report = await engine.sync(user);
      if (!ref.mounted) return;
      _failures = 0;
      final issues = report.issues;
      state = SyncStatus(
        phase: issues.isEmpty ? SyncPhase.synced : SyncPhase.error,
        lastSyncedAt: _now(),
        pending: ref.read(syncQueueProvider).length,
        issues: issues,
        message: issues.isEmpty
            ? null
            : '${issues.length} change${issues.length == 1 ? '' : 's'} '
                "couldn't sync",
      );
    } on ApiException catch (e) {
      if (!ref.mounted) return;
      if (e.isNetwork) {
        state = state.copyWith(phase: SyncPhase.offline);
        _scheduleRetry();
      } else if (e.isUnauthorized) {
        // The authenticated transport already tried a refresh: the session
        // is gone; the auth gate takes over. No retry loop.
        state = state.copyWith(
          phase: SyncPhase.error,
          message: () => 'Please log in again',
        );
      } else if (e.code == ApiException.rateLimited || e.status == 429) {
        // Back off: no automatic trigger until the retry timer fires.
        _rateLimited = true;
        state = state.copyWith(
          phase: SyncPhase.error,
          message: () => 'Server busy, retrying shortly',
        );
        _scheduleRetry();
      } else {
        state = state.copyWith(
          phase: SyncPhase.error,
          message: () => e.message,
        );
        _scheduleRetry();
      }
      _setPending();
    } catch (e, st) {
      developer.log('Sync failed', name: 'Sync', error: e, stackTrace: st);
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: SyncPhase.error,
        message: () => 'Something went wrong while syncing',
      );
      _setPending();
      _scheduleRetry();
    }
  }

  /// The next retry delay for [failures] consecutive failures (1-based).
  static Duration backoffFor(int failures) {
    final ms = minBackoff.inMilliseconds * math.pow(2, failures - 1);
    return Duration(
      milliseconds: math.min(ms, maxBackoff.inMilliseconds).toInt(),
    );
  }

  void _scheduleRetry() {
    if (!_started) return;
    _failures++;
    _retryTimer?.cancel();
    _retryTimer = Timer(backoffFor(_failures), () {
      _rateLimited = false;
      unawaited(_run());
    });
  }

  void _setPending() {
    if (!ref.mounted) return;
    final n = ref.read(syncQueueProvider).length;
    if (n != state.pending) state = state.copyWith(pending: n);
  }

  void _cancelTimers() {
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
  }

  void _stop() {
    _cancelTimers();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _started = false;
  }
}
