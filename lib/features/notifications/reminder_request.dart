/// Platform-neutral description of one reminder notification.
library;

/// How a [ReminderRequest] repeats after its first fire time.
enum ReminderRepeat {
  /// Every day at the same local time.
  daily,

  /// Every week on the same weekday at the same local time.
  weekly,

  /// Fires once.
  once,
}

/// One notification to schedule, produced by `planReminders`.
///
/// Times are *local wall-clock* times; platform schedulers convert them to
/// their own representation (e.g. `TZDateTime` in `tz.local`).
class ReminderRequest {
  /// Stable notification id (see `reminderId`).
  final int id;
  final String habitId;

  /// Slot index within the habit (0..`kReminderSlotsPerHabit - 1`).
  final int slot;
  final String title;
  final String body;
  final ReminderRepeat repeat;

  /// The first time this reminder fires (local, strictly after "now" when
  /// planned). For [ReminderRepeat.weekly] its weekday is the repeat day.
  final DateTime firstFire;

  const ReminderRequest({
    required this.id,
    required this.habitId,
    required this.slot,
    required this.title,
    required this.body,
    required this.repeat,
    required this.firstFire,
  });

  int get hour => firstFire.hour;
  int get minute => firstFire.minute;

  /// ISO weekday of [firstFire] (meaningful for weekly reminders).
  int get weekday => firstFire.weekday;

  @override
  bool operator ==(Object other) =>
      other is ReminderRequest &&
      other.id == id &&
      other.habitId == habitId &&
      other.slot == slot &&
      other.title == title &&
      other.body == body &&
      other.repeat == repeat &&
      other.firstFire == firstFire;

  @override
  int get hashCode =>
      Object.hash(id, habitId, slot, title, body, repeat, firstFire);

  @override
  String toString() =>
      'ReminderRequest(#$id $habitId[$slot] ${repeat.name} @ $firstFire)';
}
