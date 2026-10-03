/// Date-only helpers.
///
/// Habit Quest reasons about *calendar days in the user's local time zone*.
/// Every date that enters the domain layer is normalised with [dateOnly] to a
/// local-midnight `DateTime` (`DateTime(y, m, d)`). Arithmetic is done with the
/// `DateTime(y, m, d + n)` constructor (never by adding `Duration(days: n)`),
/// and day differences are computed in UTC, so daylight-saving transitions
/// can never shift a date or produce an off-by-one.
library;

/// Strips the time of day: returns local midnight of [d]'s calendar day.
///
/// UTC inputs (e.g. from `table_calendar`) keep their calendar Y/M/D.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Today's date (local midnight), optionally from an injected [now].
DateTime today([DateTime Function()? now]) => dateOnly((now ?? DateTime.now)());

/// [d] plus [days] calendar days (negative to go back). DST-safe.
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

/// Number of calendar days from [from] to [to] (negative if [to] is earlier).
int daysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// Whether [a] and [b] fall on the same calendar day.
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Monday (ISO weekday 1) of the ISO week containing [d].
DateTime startOfIsoWeek(DateTime d) => addDays(d, -(d.weekday - DateTime.monday));

/// Sunday (ISO weekday 7) of the ISO week containing [d].
DateTime endOfIsoWeek(DateTime d) => addDays(startOfIsoWeek(d), 6);

/// First day of [d]'s month.
DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);

/// Number of days in [d]'s month.
int daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

/// Stable storage key for a date: `yyyy-MM-dd`.
String dateKey(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Parses a key produced by [dateKey] back into a local date.
DateTime parseDateKey(String key) {
  final parts = key.split('-');
  if (parts.length != 3) {
    throw FormatException('Invalid date key', key);
  }
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}
