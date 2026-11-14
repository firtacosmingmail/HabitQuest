/// Small JSON helpers shared by the projects models.
library;

DateTime? parseOptionalTimestamp(Object? v) =>
    v == null ? null : DateTime.parse(v as String);

String? formatOptionalTimestamp(DateTime? t) => t?.toUtc().toIso8601String();

String formatTimestamp(DateTime t) => t.toUtc().toIso8601String();
