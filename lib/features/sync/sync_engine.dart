import '../../core/utils/stamps.dart';
import '../../data/models/check_in.dart';
import '../../data/remote/api_exception.dart';
import '../../data/remote/habit_quest_api.dart';
import '../../data/remote/remote_models.dart';
import '../../data/sync/change_recorder.dart';
import '../../data/sync/sync_meta.dart';
import '../../data/sync/sync_queue.dart';
import '../../domain/habit_service.dart';
import '../game/game_engine.dart';
import '../game/game_state.dart';
import '../projects/data/project_repository.dart';
import '../projects/domain/project_service.dart';
import 'remote_mapping.dart';

/// A change the server refused (validation error). It stays queued and is
/// reported; it never blocks the rest of the queue.
class SyncIssue {
  final SyncEntityType type;
  final String id;
  final String message;

  const SyncIssue(this.type, this.id, this.message);

  @override
  String toString() => 'SyncIssue(${type.name}:$id, $message)';
}

/// What one [SyncEngine.sync] run did.
class SyncReport {
  int pushed = 0;
  int pulledHabits = 0;
  int pulledCheckIns = 0;

  /// Projects records of every kind that replaced (or added) local ones.
  int pulledProjectRecords = 0;
  bool gameStatePushed = false;
  final List<SyncIssue> issues = [];

  @override
  String toString() =>
      'SyncReport(pushed: $pushed, pulled: $pulledHabits habits / '
      '$pulledCheckIns check-ins / $pulledProjectRecords projects records, '
      'game pushed: $gameStatePushed, '
      'issues: $issues)';
}

/// What [SyncEngine.prepareForUser] did with the local data.
enum AccountChange {
  /// The local data already belongs to this user.
  none,

  /// Local data created before any login was adopted by this user and
  /// queued for upload.
  claimed,

  /// The local data belonged to another user and was wiped.
  switched,
}

/// One offline-first sync run: push the queue, pull deltas, merge the game
/// state. Stateless between runs apart from the queue and [SyncMeta].
///
/// * Push: parents before children, because the server rejects a child
///   whose parent it does not have: habits → check-ins, then projects →
///   goals and time blocks → plan tasks, consistent actions and session
///   marks ([ProjectResource] order). Through the batch endpoints in chunks of
///   [batchSize] (the server's limit). Every acknowledged entry is dropped,
///   whether the server applied it or kept a newer row (which the pull then
///   brings). A batch refused for a validation reason is retried item by
///   item so only the offending entities are kept (with their error).
/// * Pull: `since` the per-user cursors (the `serverTime` of the previous
///   pull), merged with last-write-wins on `updatedAt` (remote replaces local
///   only when strictly newer) and applied through
///   [HabitService.applyRemote] / [ProjectService.applyRemote], which emit
///   no XP-awarding events (the projects one announces the changes on
///   `ProjectService.remoteChanges`, so the UI, the notifications and the
///   calendar refresh).
/// * Game state: GET, union-merge + reconcile ([GameEngine.reconcileSynced],
///   silent; the pulled check-ins and projects records grant their XP once,
///   without a celebration), PUT back if the merge differs from the server's copy.
///
/// Transient failures (network, 401 after refresh, 5xx, rate limiting,
/// malformed responses) are thrown as [ApiException] and abort the run; the
/// queue keeps everything not acknowledged yet.
class SyncEngine {
  final HabitQuestApi api;
  final HabitService service;
  final ProjectService projects;
  final GameEngine game;
  final SyncQueue queue;
  final SyncMeta meta;
  final DateTime Function() _now;

  static const batchSize = 500;

  SyncEngine({
    required this.api,
    required this.service,
    required this.projects,
    required this.game,
    required this.queue,
    required this.meta,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Ties the local data to [userId] before syncing (see [AccountChange]).
  Future<AccountChange> prepareForUser(String userId) async {
    final owner = meta.ownerUserId;
    if (owner == userId) return AccountChange.none;
    if (owner == null) {
      // First login on a device with data from before accounts existed (or
      // from signed-out use): upload it into this account.
      await meta.setOwner(userId);
      final repo = service.repository;
      for (final h in repo.getAllHabitRecords()) {
        await queue.recordChange(SyncEntityType.habit, h.id);
      }
      for (final c in repo.getAllCheckIns()) {
        await queue.recordChange(SyncEntityType.checkIn, c.key);
      }
      for (final r in ProjectResource.values) {
        for (final id in localProjectIds(projects.repository, r)) {
          await queue.recordChange(syncTypeOf(r), id);
        }
      }
      if (game.state != GameState.empty) {
        await queue.recordChange(SyncEntityType.gameState, gameStateId);
      }
      return AccountChange.claimed;
    }
    // Another account's data: never upload it into this one.
    await queue.clear();
    await meta.clear();
    await service.clearLocalData();
    await projects.clearLocalData();
    await game.resetSilently();
    await meta.setOwner(userId);
    return AccountChange.switched;
  }

  /// Pushes, pulls and merges for [userId] (who must own the local data,
  /// see [prepareForUser]).
  Future<SyncReport> sync(String userId) async {
    final report = SyncReport();
    await _pushHabits(report);
    await _pushCheckIns(report);
    for (final r in ProjectResource.values) {
      await _pushProjectRecords(r, report);
    }
    final applied = await _pull(userId, report);
    final appliedProjects = await _pullProjects(userId, report);
    await _syncGameState(applied, appliedProjects, report);
    for (final e in queue.failed) {
      report.issues.add(SyncIssue(e.type, e.id, e.lastError!));
    }
    await meta.setLastSyncedAt(userId, _now());
    return report;
  }

  // Push ---------------------------------------------------------------------

  Future<void> _pushHabits(SyncReport report) => _push<RemoteHabit>(
    report,
    entries: queue.entriesOf(SyncEntityType.habit),
    load: (e) {
      final h = service.repository.getHabitRecord(e.id);
      return h == null ? null : habitToRemote(h);
    },
    batch: api.batchHabits,
    put: api.putHabit,
    delete: api.deleteHabit,
  );

  Future<void> _pushCheckIns(SyncReport report) => _push<RemoteCheckIn>(
    report,
    entries: queue.entriesOf(SyncEntityType.checkIn),
    load: (e) {
      final p = CheckIn.parseKey(e.id);
      if (p == null) return null;
      final c = service.repository.getCheckIn(p.$1, p.$2);
      return c == null ? null : checkInToRemote(c);
    },
    batch: api.batchCheckIns,
    put: api.putCheckIn,
    delete: api.deleteCheckIn,
  );

  Future<void> _pushProjectRecords(ProjectResource r, SyncReport report) =>
      _push<RemoteProjectRecord>(
        report,
        entries: queue.entriesOf(syncTypeOf(r)),
        load: (e) => localProjectRecord(projects.repository, r, e.id),
        batch: (items) => api.batchProjectRecords(r, items),
        put: api.putProjectRecord,
        delete: (id, {required updatedAt}) =>
            api.deleteProjectRecord(r, id, updatedAt: updatedAt),
        // The server returns UUIDs in lower case.
        idKey: (id) => id.toLowerCase(),
      );

  Future<void> _push<R extends RemoteEntity>(
    SyncReport report, {
    required List<SyncQueueEntry> entries,
    required R? Function(SyncQueueEntry) load,
    required Future<List<BatchItemResult<R>>> Function(List<R>) batch,
    required Future<WriteResult<R>> Function(R) put,
    required Future<WriteResult<R>> Function(
      String, {
      required DateTime updatedAt,
    })
    delete,
    String Function(String id)? idKey,
  }) async {
    final key = idKey ?? (String id) => id;
    final fresh = <(SyncQueueEntry, R)>[];
    final retry = <(SyncQueueEntry, R)>[];
    for (final e in entries) {
      final item = load(e);
      if (item == null) {
        // Nothing left to send (e.g. a check-in removed with its habit).
        await queue.ack(e);
        continue;
      }
      (e.hasError ? retry : fresh).add((e, item));
    }

    for (var i = 0; i < fresh.length; i += batchSize) {
      final chunk = fresh.sublist(
        i,
        i + batchSize > fresh.length ? fresh.length : i + batchSize,
      );
      try {
        final results = await batch([for (final c in chunk) c.$2]);
        final byId = {for (final r in results) key(r.id): r};
        for (final (entry, item) in chunk) {
          if (byId.containsKey(key(item.id))) {
            await queue.ack(entry);
            report.pushed++;
          }
        }
      } on ApiException catch (e) {
        if (!_isEntityError(e)) rethrow;
        // One bad entity must not block the others: go item by item.
        retry.addAll(chunk);
      }
    }

    for (final (entry, item) in retry) {
      try {
        if (item.deletedAt != null) {
          // A tombstone: soft DELETE, always with our updatedAt so LWW holds
          // (without it the server would stamp its own time).
          try {
            await delete(item.id, updatedAt: item.updatedAt);
          } on ApiException catch (e) {
            // The server never had it: nothing to delete, acknowledged.
            if (e.status != 404 || e.code != ApiException.notFound) rethrow;
          }
        } else {
          await put(item);
        }
        await queue.ack(entry);
        report.pushed++;
      } on ApiException catch (e) {
        if (!_isEntityError(e)) rethrow;
        await queue.markFailed(entry, '${e.code}: ${e.message}');
      }
    }
  }

  /// Errors caused by the entity itself (keep it, carry on with the rest),
  /// as opposed to transient / session errors that abort the run.
  static bool _isEntityError(ApiException e) {
    final s = e.status;
    if (s == null || e.isUnauthorized) return false;
    return e.code == ApiException.invalidInput ||
        e.code == ApiException.habitNotFound ||
        e.code == ApiException.notFound ||
        (s >= 400 && s < 500 && s != 401 && s != 408 && s != 429);
  }

  // Pull ---------------------------------------------------------------------

  /// Returns the check-ins that replaced local ones.
  Future<List<CheckIn>> _pull(String userId, SyncReport report) async {
    final repo = service.repository;

    final habitsPage = await api.listHabits(since: meta.habitsCursor(userId));
    final habits = [
      for (final r in habitsPage.items)
        if (_remoteWins(r.updatedAt, repo.getHabitRecord(r.id)?.updatedAt))
          habitFromRemote(r),
    ];
    await service.applyRemote(habits: habits);
    await meta.setHabitsCursor(userId, habitsPage.serverTime);
    report.pulledHabits = habits.length;

    final checkInsPage = await api.listCheckIns(
      since: meta.checkInsCursor(userId),
    );
    final checkIns = [
      for (final r in checkInsPage.items)
        if (_remoteWins(
          r.updatedAt,
          repo.getCheckIn(r.habitId, r.date)?.updatedAt,
        ))
          checkInFromRemote(r),
    ];
    await service.applyRemote(checkIns: checkIns);
    await meta.setCheckInsCursor(userId, checkInsPage.serverTime);
    report.pulledCheckIns = checkIns.length;

    return checkIns;
  }

  /// Pulls the six Projects resources (parents first) since their cursors
  /// and applies the LWW winners in one [ProjectService.applyRemote].
  /// Returns what was applied (for the XP reconcile).
  Future<ProjectRecords> _pullProjects(String userId, SyncReport report) async {
    final repo = projects.repository;
    final winners = <RemoteProjectRecord>[];
    final cursors = <ProjectResource, DateTime>{};
    for (final r in ProjectResource.values) {
      final page = await api.listProjectRecords(
        r,
        since: meta.projectsCursor(userId, r.function),
      );
      for (final item in page.items) {
        final local = localProjectRecord(repo, r, item.id);
        if (_remoteWins(item.updatedAt, local?.updatedAt)) winners.add(item);
      }
      cursors[r] = page.serverTime;
    }
    final records = _readProjectRecords(winners);
    await projects.applyRemote(records);
    for (final MapEntry(:key, :value) in cursors.entries) {
      await meta.setProjectsCursor(userId, key.function, value);
    }
    report.pulledProjectRecords =
        records.projects.length +
        records.goals.length +
        records.timeBlocks.length +
        records.planTasks.length +
        records.consistentActions.length +
        records.sessionMarks.length;
    return records;
  }

  /// Maps the pulled records, skipping any the models cannot read (e.g. a
  /// newer schema) rather than failing every sync.
  static ProjectRecords _readProjectRecords(List<RemoteProjectRecord> items) {
    try {
      return projectRecordsFromRemote(items);
    } on Object {
      return projectRecordsFromRemote([
        for (final i in items)
          if (_readable(i)) i,
      ]);
    }
  }

  static bool _readable(RemoteProjectRecord r) {
    try {
      projectRecordsFromRemote([r]);
      return true;
    } on Object {
      return false;
    }
  }

  /// Last-write-wins: the remote copy replaces the local one only if it is
  /// strictly newer (equal = keep local).
  static bool _remoteWins(DateTime remote, DateTime? local) =>
      local == null || remote.isAfter(local);

  // Game state ---------------------------------------------------------------

  Future<void> _syncGameState(
    List<CheckIn> applied,
    ProjectRecords appliedProjects,
    SyncReport report,
  ) async {
    // Snapshot: a local change made while this runs stays queued.
    var entry = queue.entryFor(SyncEntityType.gameState, gameStateId);
    for (var attempt = 0; attempt < 2; attempt++) {
      final snap = await api.getGameState();
      final remote = _remoteState(snap.item);
      final merged = await game.reconcileSynced(
        remote: remote,
        appliedCheckIns: attempt == 0 ? applied : const [],
        appliedProjects: attempt == 0 ? appliedProjects : null,
      );
      final needsPush = remote == null
          ? (merged != GameState.empty || entry != null)
          : merged != remote;
      if (!needsPush) {
        if (entry != null) await queue.ack(entry);
        return;
      }
      final previous = _latest(merged.updatedAt, remote?.updatedAt);
      final stamp = nextStamp(_now(), previous);
      final payload = merged.copyWith(updatedAt: stamp);
      try {
        final res = await api.putGameState(
          RemoteGameState(state: payload.toJson(), updatedAt: stamp),
        );
        if (res.applied) {
          if (entry != null) await queue.ack(entry);
          report.gameStatePushed = true;
          return;
        }
        // Another device wrote in between: merge with that and try again.
      } on ApiException catch (e) {
        if (!_isEntityError(e)) rethrow;
        if (entry == null) {
          await queue.recordChange(SyncEntityType.gameState, gameStateId);
          entry = queue.entryFor(SyncEntityType.gameState, gameStateId);
        }
        await queue.markFailed(entry!, '${e.code}: ${e.message}');
        return;
      }
    }
    // Still racing: keep it queued for the next run.
    if (entry == null) {
      await queue.recordChange(SyncEntityType.gameState, gameStateId);
    }
  }

  static GameState? _remoteState(RemoteGameState? r) {
    if (r == null) return null;
    try {
      return GameState.fromJson(r.state).copyWith(updatedAt: r.updatedAt);
    } on Object {
      // Unreadable remote state (e.g. a future schema): treat as absent and
      // overwrite it with ours rather than fail every sync.
      return null;
    }
  }

  static DateTime? _latest(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }
}
