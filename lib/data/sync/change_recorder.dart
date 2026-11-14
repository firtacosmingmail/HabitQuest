/// The kinds of entities that sync.
///
/// The projects kinds (`project` … `sessionMark`) are recorded by
/// `CachedProjectRepository` once it is given a recorder; the sync engine
/// does not push / pull them yet (see docs/PROJECTS.md "Sync").
enum SyncEntityType {
  habit,
  checkIn,
  gameState,
  project,
  target,
  planTask,
  consistentAction,
  sessionMark,
}

/// Receives "this entity changed locally" notes from the repositories, so
/// the change can be pushed later (implemented by `SyncQueue`).
///
/// Repositories call it for local writes only, never when applying data
/// that came from the server.
abstract interface class ChangeRecorder {
  /// [id] is the habit id, the check-in key (`habitId|yyyy-MM-dd`),
  /// [gameStateId], a projects record id, or a session mark key
  /// (`actionId|yyyy-MM-dd`).
  Future<void> recordChange(SyncEntityType type, String id);
}

/// The id used for the (single) game state.
const gameStateId = 'game';
