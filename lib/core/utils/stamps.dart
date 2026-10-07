/// A last-write-wins timestamp for a local write: [now] in UTC, bumped to
/// 1 ms after [previous] when the clock did not move forward (fast
/// successive writes, or a clock that went backwards), so a newer local
/// write always carries a strictly newer `updatedAt`.
DateTime nextStamp(DateTime now, [DateTime? previous]) {
  final t = now.toUtc();
  if (previous == null || t.isAfter(previous)) return t;
  return previous.toUtc().add(const Duration(milliseconds: 1));
}
