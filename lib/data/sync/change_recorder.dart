/// The kinds of entities that sync.
///
/// The projects kinds (`project` … `sessionMark`) are recorded by
/// `CachedProjectRepository` (given the queue in `main.dart`) and pushed /
/// pulled by `SyncEngine` like habits (README "Sync").
enum SyncEntityType {
  habit,
  checkIn,
  gameState,
  project,
  goal,
  planTask,
  timeBlock,

  /// The goal's text items (docs/PROJECTS.md). Before the Projects rework
  /// (local schema v2) this name meant the recurring time blocks; the
  /// local migration (`migrateProjectsStorage`) renames those queue
  /// entries to [timeBlock] before the queue is loaded.
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
  /// (`timeBlockId|yyyy-MM-dd`).
  Future<void> recordChange(SyncEntityType type, String id);
}

/// The id used for the (single) game state.
const gameStateId = 'game';
