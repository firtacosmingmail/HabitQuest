/// How often a habit is due. Use an exhaustive `switch` over the subclasses.
///
/// * [DailySchedule] – every day.
/// * [WeekdaysSchedule] – on specific ISO weekdays (1 = Monday … 7 = Sunday).
/// * [EveryNDaysSchedule] – every [EveryNDaysSchedule.n] days, counted from the
///   habit's `startDate` (start date is always due).
/// * [TimesPerWeekSchedule] – [TimesPerWeekSchedule.times] check-ins per ISO
///   week; due on any day until the target is reached that week.
sealed class HabitSchedule {
  const HabitSchedule();

  /// Serialises to a JSON-compatible map (`{'type': ..., ...}`).
  Map<String, dynamic> toJson();

  /// Inverse of [toJson]. Throws [FormatException] on unknown types.
  static HabitSchedule fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    switch (type) {
      case DailySchedule.typeName:
        return const DailySchedule();
      case WeekdaysSchedule.typeName:
        return WeekdaysSchedule(
          (json['days'] as List).map((e) => (e as num).toInt()).toSet(),
        );
      case EveryNDaysSchedule.typeName:
        return EveryNDaysSchedule((json['n'] as num).toInt());
      case TimesPerWeekSchedule.typeName:
        return TimesPerWeekSchedule((json['times'] as num).toInt());
      default:
        throw FormatException('Unknown schedule type', type);
    }
  }
}

final class DailySchedule extends HabitSchedule {
  static const typeName = 'daily';

  const DailySchedule();

  @override
  Map<String, dynamic> toJson() => {'type': typeName};

  @override
  bool operator ==(Object other) => other is DailySchedule;

  @override
  int get hashCode => typeName.hashCode;

  @override
  String toString() => 'DailySchedule()';
}

final class WeekdaysSchedule extends HabitSchedule {
  static const typeName = 'weekdays';

  /// ISO weekdays (`DateTime.monday` = 1 … `DateTime.sunday` = 7). Non-empty.
  final Set<int> days;

  WeekdaysSchedule(Set<int> days) : days = Set.unmodifiable(days) {
    if (days.isEmpty || days.any((d) => d < 1 || d > 7)) {
      throw ArgumentError.value(days, 'days', 'must be a non-empty set of 1..7');
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': typeName,
        'days': (days.toList()..sort()),
      };

  @override
  bool operator ==(Object other) =>
      other is WeekdaysSchedule &&
      other.days.length == days.length &&
      other.days.containsAll(days);

  @override
  int get hashCode => Object.hashAllUnordered(days);

  @override
  String toString() => 'WeekdaysSchedule(${days.toList()..sort()})';
}

final class EveryNDaysSchedule extends HabitSchedule {
  static const typeName = 'everyNDays';

  /// Interval in days (>= 1). `n == 1` behaves like daily.
  final int n;

  EveryNDaysSchedule(this.n) {
    if (n < 1) throw ArgumentError.value(n, 'n', 'must be >= 1');
  }

  @override
  Map<String, dynamic> toJson() => {'type': typeName, 'n': n};

  @override
  bool operator ==(Object other) => other is EveryNDaysSchedule && other.n == n;

  @override
  int get hashCode => Object.hash(typeName, n);

  @override
  String toString() => 'EveryNDaysSchedule($n)';
}

final class TimesPerWeekSchedule extends HabitSchedule {
  static const typeName = 'timesPerWeek';

  /// Target check-ins per ISO week (1..7).
  final int times;

  TimesPerWeekSchedule(this.times) {
    if (times < 1 || times > 7) {
      throw ArgumentError.value(times, 'times', 'must be in 1..7');
    }
  }

  @override
  Map<String, dynamic> toJson() => {'type': typeName, 'times': times};

  @override
  bool operator ==(Object other) =>
      other is TimesPerWeekSchedule && other.times == times;

  @override
  int get hashCode => Object.hash(typeName, times);

  @override
  String toString() => 'TimesPerWeekSchedule($times)';
}
