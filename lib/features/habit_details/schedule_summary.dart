import '../../core/constants/habit_defaults.dart';
import '../../data/models/habit_schedule.dart';

/// Short human summary of a schedule: 'Every day', 'Mon · Wed · Fri',
/// 'Every 3 days', '3× per week'.
String scheduleSummary(HabitSchedule schedule) => switch (schedule) {
      DailySchedule() => 'Every day',
      WeekdaysSchedule(:final days) when days.length == 7 => 'Every day',
      WeekdaysSchedule(:final days) => (days.toList()..sort())
          .map((d) => HabitDefaults.weekdayShort[d]!)
          .join(' · '),
      EveryNDaysSchedule(:final n) when n == 1 => 'Every day',
      EveryNDaysSchedule(:final n) => 'Every $n days',
      TimesPerWeekSchedule(:final times) => '$times× per week',
    };
