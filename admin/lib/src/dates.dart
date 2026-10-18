/// Calendar-day helpers, copied from the mobile app's
/// lib/core/utils/dates.dart (kept separate on purpose: the console never
/// imports from the root lib/). Dates are local midnights; arithmetic uses
/// `DateTime(y, m, d + n)` so DST never shifts a day.
library;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

int daysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// Monday of the ISO week containing [d].
DateTime startOfIsoWeek(DateTime d) =>
    addDays(d, -(d.weekday - DateTime.monday));

/// `yyyy-MM-dd`.
String dateKey(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Parses a [dateKey] (or the date part of an ISO timestamp).
DateTime parseDateKey(String key) {
  final parts = key.substring(0, 10).split('-');
  if (parts.length != 3) throw FormatException('Invalid date key', key);
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// `14 Oct`.
String shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// `Wed 14 Oct 2026`.
String longDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} ${d.year}';

String weekdayName(DateTime d) => _weekdays[d.weekday - 1];
