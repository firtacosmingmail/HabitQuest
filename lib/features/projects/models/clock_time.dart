/// A local wall-clock time of day (`HH:mm`), independent of Flutter's
/// `TimeOfDay` so the projects data layer stays pure Dart.
///
/// JSON: the string `"HH:mm"` (24 h, zero-padded), e.g. `"09:30"`.
class ClockTime implements Comparable<ClockTime> {
  final int hour; // 0..23
  final int minute; // 0..59

  const ClockTime(this.hour, this.minute)
      : assert(hour >= 0 && hour < 24),
        assert(minute >= 0 && minute < 60);

  /// Minutes since local midnight (0..1439).
  int get minutesOfDay => hour * 60 + minute;

  /// Parses `"HH:mm"` (also accepts `"H:mm"`). Throws [FormatException].
  factory ClockTime.parse(String s) {
    final parts = s.split(':');
    if (parts.length != 2) throw FormatException('Invalid time', s);
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      throw FormatException('Invalid time', s);
    }
    return ClockTime(h, m);
  }

  /// [date]'s calendar day at this wall-clock time (local). On a DST
  /// "spring forward" day a time inside the skipped hour is moved forward
  /// by the platform (e.g. 02:30 → 03:30); see docs/PROJECTS.md.
  DateTime on(DateTime date) =>
      DateTime(date.year, date.month, date.day, hour, minute);

  String toJson() => toString();

  @override
  int compareTo(ClockTime other) => minutesOfDay - other.minutesOfDay;

  bool isBefore(ClockTime other) => minutesOfDay < other.minutesOfDay;

  @override
  bool operator ==(Object other) =>
      other is ClockTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
