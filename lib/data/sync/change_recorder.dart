/// The kinds of entities that sync.
enum SyncEntityType { habit, checkIn, gameState }

/// Receives "this entity changed locally" notes from the repositories, so
/// the change can be pushed later (implemented by `SyncQueue`).
///
/// Repositories call it for local writes only, never when applying data
/// that came from the server.
abstract interface class ChangeRecorder {
  /// [id] is the habit id, the check-in key (`habitId|yyyy-MM-dd`) or
  /// [gameStateId].
  Future<void> recordChange(SyncEntityType type, String id);
}

/// The id used for the (single) game state.
const gameStateId = 'game';
