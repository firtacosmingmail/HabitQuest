import 'remote_models.dart';

/// The data Edge Functions (`habits`, `check-ins`, `game-state` and the
/// five Projects functions, see [ProjectResource]) for the
/// signed-in user. Implementations attach the access token themselves
/// (refreshing it on 401 once). Every method throws [ApiException] on
/// failure; `ApiException.isNetwork` means "offline, retry later".
///
/// Writes use last-write-wins on `updatedAt` (strictly newer wins); a losing
/// write returns `applied: false` and the stored row in `item`.
abstract interface class HabitQuestApi {
  // Habits ------------------------------------------------------------------

  /// All habits (tombstones included) changed after [since]; all of them
  /// when [since] is null.
  Future<DeltaPage<RemoteHabit>> listHabits({DateTime? since});

  /// A habit (tombstones included), or `null` when unknown (404).
  Future<RemoteHabit?> getHabit(String id);

  /// Upsert with LWW (`PUT /habits/<id>`).
  Future<WriteResult<RemoteHabit>> putHabit(RemoteHabit habit);

  /// Soft delete with LWW. Throws `not_found` (404) for an unknown id.
  Future<WriteResult<RemoteHabit>> deleteHabit(
    String id, {
    required DateTime updatedAt,
  });

  /// Upserts up to 500 habits (tombstones too) in order.
  Future<List<BatchItemResult<RemoteHabit>>> batchHabits(
    List<RemoteHabit> habits,
  );

  // Check-ins ---------------------------------------------------------------

  Future<DeltaPage<RemoteCheckIn>> listCheckIns({
    DateTime? since,
    String? habitId,
  });

  Future<RemoteCheckIn?> getCheckIn(String id);

  /// Throws `habit_not_found` (409) if the habit is not on the server yet.
  Future<WriteResult<RemoteCheckIn>> putCheckIn(RemoteCheckIn checkIn);

  Future<WriteResult<RemoteCheckIn>> deleteCheckIn(
    String id, {
    required DateTime updatedAt,
  });

  /// Throws `habit_not_found` (409) and writes nothing if any check-in's
  /// habit is missing on the server.
  Future<List<BatchItemResult<RemoteCheckIn>>> batchCheckIns(
    List<RemoteCheckIn> checkIns,
  );

  // Game state --------------------------------------------------------------

  Future<GameStateSnapshot> getGameState();

  Future<WriteResult<RemoteGameState>> putGameState(RemoteGameState state);

  /// Removes the user's game state (reset).
  Future<void> deleteGameState();

  // Projects ----------------------------------------------------------------
  // One generic set for the five Projects functions: same routes and
  // semantics as habits (supabase/API.md "Projects"). A child whose parent
  // is not on the server yet fails with `409 parent_not_found` (a batch is
  // all-or-nothing).

  /// Records of [resource] (tombstones included) changed after [since].
  Future<DeltaPage<RemoteProjectRecord>> listProjectRecords(
    ProjectResource resource, {
    DateTime? since,
  });

  /// Upsert with LWW (`PUT /<function>/<id>`).
  Future<WriteResult<RemoteProjectRecord>> putProjectRecord(
    RemoteProjectRecord record,
  );

  /// Soft delete with LWW. Throws `not_found` (404) for an unknown id.
  Future<WriteResult<RemoteProjectRecord>> deleteProjectRecord(
    ProjectResource resource,
    String id, {
    required DateTime updatedAt,
  });

  /// Upserts up to 500 records of [resource] (tombstones too) in order.
  Future<List<BatchItemResult<RemoteProjectRecord>>> batchProjectRecords(
    ProjectResource resource,
    List<RemoteProjectRecord> records,
  );
}
