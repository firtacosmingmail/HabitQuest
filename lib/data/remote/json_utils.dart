import 'package:intl/intl.dart';

import 'api_exception.dart';

/// Contract timestamp format: ISO-8601 UTC with milliseconds
/// (`2026-10-07T09:15:00.000Z`).
String formatTimestamp(DateTime t) {
  final u = t.toUtc();
  // DateTime.toIso8601String prints microseconds when present; the contract
  // wants exactly milliseconds.
  final ms = DateTime.utc(
    u.year,
    u.month,
    u.day,
    u.hour,
    u.minute,
    u.second,
    u.millisecond,
  );
  return ms.toIso8601String();
}

/// Parses a contract timestamp (any ISO-8601 with zone) into UTC.
DateTime parseTimestamp(Object? value, String field) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  throw ApiException(
    code: ApiException.badResponse,
    message: 'Invalid timestamp in "$field": $value',
  );
}

DateTime? parseTimestampOrNull(Object? value, String field) =>
    value == null ? null : parseTimestamp(value, field);

final _dateFormat = DateFormat('yyyy-MM-dd');

/// Contract date format `yyyy-MM-dd`.
String formatDate(DateTime d) => _dateFormat.format(d);

/// Parses `yyyy-MM-dd` into a local-midnight [DateTime] (the app's date
/// convention, see `core/utils/dates.dart`).
DateTime parseDate(Object? value, String field) {
  if (value is String) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (m != null) {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
    }
  }
  throw ApiException(
    code: ApiException.badResponse,
    message: 'Invalid date in "$field": $value',
  );
}

String readString(Map<String, dynamic> json, String field) {
  final v = json[field];
  if (v is String) return v;
  throw ApiException(
    code: ApiException.badResponse,
    message: 'Missing string "$field"',
  );
}

Map<String, dynamic> readObject(Map<String, dynamic> json, String field) {
  final v = json[field];
  if (v is Map<String, dynamic>) return v;
  throw ApiException(
    code: ApiException.badResponse,
    message: 'Missing object "$field"',
  );
}

List<Map<String, dynamic>> readObjectList(
  Map<String, dynamic> json,
  String field,
) {
  final v = json[field];
  if (v is List) return v.cast<Map<String, dynamic>>();
  throw ApiException(
    code: ApiException.badResponse,
    message: 'Missing list "$field"',
  );
}
