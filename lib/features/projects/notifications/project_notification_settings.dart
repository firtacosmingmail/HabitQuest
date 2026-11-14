/// The three Projects notification toggles (Settings), stored locally.
library;

import 'dart:async';
import 'dart:convert';

import '../../../data/sync/string_store.dart';

/// Which Projects notifications are on. All default to on.
class ProjectNotificationSettings {
  /// "Work split starts": at the start time of each session.
  final bool workSplits;

  /// "Deadlines": 3 days before, 1 day before and the morning of a
  /// target's deadline.
  final bool deadlines;

  /// "Task deliveries": the day before a plan task's delivery date.
  final bool taskDeliveries;

  const ProjectNotificationSettings({
    this.workSplits = true,
    this.deadlines = true,
    this.taskDeliveries = true,
  });

  static const allOn = ProjectNotificationSettings();
  static const allOff = ProjectNotificationSettings(
    workSplits: false,
    deadlines: false,
    taskDeliveries: false,
  );

  bool get anyOn => workSplits || deadlines || taskDeliveries;

  ProjectNotificationSettings copyWith({
    bool? workSplits,
    bool? deadlines,
    bool? taskDeliveries,
  }) => ProjectNotificationSettings(
    workSplits: workSplits ?? this.workSplits,
    deadlines: deadlines ?? this.deadlines,
    taskDeliveries: taskDeliveries ?? this.taskDeliveries,
  );

  Map<String, dynamic> toJson() => {
    'workSplits': workSplits,
    'deadlines': deadlines,
    'taskDeliveries': taskDeliveries,
  };

  /// Missing / malformed values fall back to on.
  factory ProjectNotificationSettings.fromJson(Map<String, dynamic> json) =>
      ProjectNotificationSettings(
        workSplits: json['workSplits'] as bool? ?? true,
        deadlines: json['deadlines'] as bool? ?? true,
        taskDeliveries: json['taskDeliveries'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      other is ProjectNotificationSettings &&
      other.workSplits == workSplits &&
      other.deadlines == deadlines &&
      other.taskDeliveries == taskDeliveries;

  @override
  int get hashCode => Object.hash(workSplits, deadlines, taskDeliveries);

  @override
  String toString() =>
      'ProjectNotificationSettings(workSplits: $workSplits, '
      'deadlines: $deadlines, taskDeliveries: $taskDeliveries)';
}

/// Persists [ProjectNotificationSettings] in a [StringStore] (a hive box in
/// the app, memory in tests) and announces every change.
///
/// Device-local on purpose: notifications are per device, so the toggles
/// are not synced and survive sign-out.
class ProjectNotificationSettingsStore {
  static const boxName = 'project_notification_settings';
  static const _key = 'settings';

  final StringStore _store;
  final _changes = StreamController<ProjectNotificationSettings>.broadcast();
  ProjectNotificationSettings _value;

  ProjectNotificationSettingsStore(this._store) : _value = _read(_store);

  static ProjectNotificationSettings _read(StringStore store) {
    final raw = store.get(_key);
    if (raw == null) return ProjectNotificationSettings.allOn;
    try {
      return ProjectNotificationSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return ProjectNotificationSettings.allOn;
    }
  }

  ProjectNotificationSettings get value => _value;

  /// Emits the new value after each [update] that changed something.
  Stream<ProjectNotificationSettings> get changes => _changes.stream;

  Future<void> update(ProjectNotificationSettings next) async {
    if (next == _value) return;
    _value = next;
    _changes.add(next);
    await _store.put(_key, jsonEncode(next.toJson()));
  }

  Future<void> dispose() => _changes.close();
}
