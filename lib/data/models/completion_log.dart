import '../../core/utils/dates.dart';

/// Immutable snapshot of all check-ins: for each habit id, the set of
/// completed dates (stored as `yyyy-MM-dd` keys, see `dateKey`).
class CompletionLog {
  final Map<String, Set<String>> _byHabit;

  const CompletionLog.empty() : _byHabit = const {};

  /// Builds a log from `habitId -> dates`. Dates are normalised to day keys.
  factory CompletionLog.fromDates(Map<String, Iterable<DateTime>> dates) =>
      CompletionLog.fromKeys({
        for (final e in dates.entries) e.key: e.value.map(dateKey),
      });

  /// Builds a log from `habitId -> yyyy-MM-dd keys`.
  CompletionLog.fromKeys(Map<String, Iterable<String>> keys)
      : _byHabit = Map.unmodifiable({
          for (final e in keys.entries)
            if (e.value.isNotEmpty) e.key: Set<String>.unmodifiable(e.value),
        });

  /// Whether [habitId] was checked in on [date]'s calendar day.
  bool isCompleted(String habitId, DateTime date) =>
      _byHabit[habitId]?.contains(dateKey(date)) ?? false;

  /// Completed day keys for [habitId] (empty if none).
  Set<String> keysFor(String habitId) => _byHabit[habitId] ?? const {};

  /// Completed dates (local midnight) for [habitId], sorted ascending.
  List<DateTime> datesFor(String habitId) =>
      (keysFor(habitId).toList()..sort()).map(parseDateKey).toList();

  /// Number of check-ins of [habitId] in the inclusive range [from]..[to].
  int countInRange(String habitId, DateTime from, DateTime to) {
    final lo = dateKey(from);
    final hi = dateKey(to);
    var count = 0;
    for (final k in keysFor(habitId)) {
      if (k.compareTo(lo) >= 0 && k.compareTo(hi) <= 0) count++;
    }
    return count;
  }

  /// Total number of check-ins of [habitId].
  int totalFor(String habitId) => keysFor(habitId).length;

  /// Habit ids that have at least one check-in.
  Iterable<String> get habitIds => _byHabit.keys;

  /// Returns a copy with [habitId] on [date] set to [completed].
  CompletionLog withCompletion(String habitId, DateTime date, bool completed) {
    final copy = {for (final e in _byHabit.entries) e.key: {...e.value}};
    final set = copy.putIfAbsent(habitId, () => <String>{});
    completed ? set.add(dateKey(date)) : set.remove(dateKey(date));
    return CompletionLog.fromKeys(copy);
  }

  @override
  bool operator ==(Object other) {
    if (other is! CompletionLog) return false;
    if (other._byHabit.length != _byHabit.length) return false;
    for (final e in _byHabit.entries) {
      final o = other._byHabit[e.key];
      if (o == null || o.length != e.value.length || !o.containsAll(e.value)) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
        _byHabit.entries.map(
          (e) => Object.hash(e.key, Object.hashAllUnordered(e.value)),
        ),
      );

  @override
  String toString() => 'CompletionLog($_byHabit)';
}
