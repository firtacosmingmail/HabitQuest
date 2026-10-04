/// Stable notification ids: `hash(habitId) * slots + slot`.
///
/// The ids only depend on the habit id and the slot index, so rescheduling a
/// habit can cancel exactly its own notifications (all slots) without
/// remembering what was scheduled before, and the result fits in a positive
/// 32-bit int as required by Android.
library;

/// Maximum number of notifications per habit (slot indices `0..15`).
const kReminderSlotsPerHabit = 16;

/// 26-bit hash space × 16 slots < 2^31.
const _hashMask = 0x3FFFFFF;

/// 32-bit FNV-1a hash of [value]'s UTF-16 code units. Deterministic across
/// runs and platforms (unlike `String.hashCode`).
int stableHash(String value) {
  var hash = 0x811C9DC5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// Notification id of [slot] (0..15) for [habitId].
int reminderId(String habitId, int slot) {
  if (slot < 0 || slot >= kReminderSlotsPerHabit) {
    throw RangeError.range(slot, 0, kReminderSlotsPerHabit - 1, 'slot');
  }
  return (stableHash(habitId) & _hashMask) * kReminderSlotsPerHabit + slot;
}

/// Every id a habit can ever use; cancel these to clear the habit.
List<int> allReminderIds(String habitId) => [
      for (var slot = 0; slot < kReminderSlotsPerHabit; slot++)
        reminderId(habitId, slot),
    ];
