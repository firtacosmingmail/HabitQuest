import 'dart:convert';
import 'dart:developer' as developer;

import 'package:hive_ce/hive.dart';

import '../../../data/sync/change_recorder.dart';
import '../models/consistent_action.dart';
import '../models/goal.dart';
import '../models/plan_task.dart';
import '../models/project.dart';
import '../models/session_mark.dart';
import '../models/time_block.dart';
import 'project_repository.dart';

/// [ProjectRepository] backed by six hive_ce boxes of JSON strings (no
/// adapters / code generation), one per [ProjectEntityKind]:
///
/// | box | key | value |
/// |---|---|---|
/// | `projects` | `id` | `Project.toJson()` |
/// | `project_goals` | `id` | `Goal.toJson()` |
/// | `project_plan_tasks` | `id` | `PlanTask.toJson()` |
/// | `project_time_blocks` | `id` | `TimeBlock.toJson()` |
/// | `project_consistent_actions` | `id` | `ConsistentAction.toJson()` |
/// | `project_session_marks` | `timeBlockId\|yyyy-MM-dd` | `SessionMark.toJson()` |
///
/// Data written before the rework (boxes `project_targets` and
/// `project_actions`) is converted once by `migrateProjectsStorage` (see
/// `projects_storage_migration.dart`), which `main.dart` runs before
/// [open].
///
/// Tombstones are stored too. Unreadable entries are skipped (logged).
/// Call `Hive.initFlutter()` (app) or `Hive.init(path)` (tests) first.
class HiveProjectRepository extends CachedProjectRepository {
  static const boxNames = {
    ProjectEntityKind.project: 'projects',
    ProjectEntityKind.goal: 'project_goals',
    ProjectEntityKind.planTask: 'project_plan_tasks',
    ProjectEntityKind.timeBlock: 'project_time_blocks',
    ProjectEntityKind.consistentAction: 'project_consistent_actions',
    ProjectEntityKind.sessionMark: 'project_session_marks',
  };

  final Map<ProjectEntityKind, Box<String>> _boxes;

  HiveProjectRepository._(this._boxes, {super.recorder});

  /// Opens (or creates) the boxes and loads them. [boxPrefix] isolates
  /// test data. Local writes are reported to [recorder] when given.
  static Future<HiveProjectRepository> open({
    String boxPrefix = '',
    ChangeRecorder? recorder,
  }) async {
    final boxes = <ProjectEntityKind, Box<String>>{
      for (final e in boxNames.entries)
        e.key: await Hive.openBox<String>('$boxPrefix${e.value}'),
    };
    final repo = HiveProjectRepository._(boxes, recorder: recorder);
    repo._load();
    return repo;
  }

  void _load() {
    List<T> read<T>(
      ProjectEntityKind kind,
      T Function(Map<String, dynamic>) fromJson,
    ) {
      final box = _boxes[kind]!;
      final out = <T>[];
      for (final key in box.keys) {
        try {
          out.add(fromJson(jsonDecode(box.get(key)!) as Map<String, dynamic>));
        } on Object catch (e) {
          developer.log('Skipping unreadable ${kind.name} $key: $e',
              name: 'Hive');
        }
      }
      return out;
    }

    cacheRecords(ProjectRecords(
      projects: read(ProjectEntityKind.project, Project.fromJson),
      goals: read(ProjectEntityKind.goal, Goal.fromJson),
      planTasks: read(ProjectEntityKind.planTask, PlanTask.fromJson),
      timeBlocks: read(ProjectEntityKind.timeBlock, TimeBlock.fromJson),
      consistentActions: read(
          ProjectEntityKind.consistentAction, ConsistentAction.fromJson),
      sessionMarks: read(ProjectEntityKind.sessionMark, SessionMark.fromJson),
    ));
  }

  @override
  Future<void> persist(
    ProjectEntityKind kind,
    Map<String, Map<String, dynamic>?> changes,
  ) async {
    final box = _boxes[kind]!;
    final puts = <String, String>{};
    final deletes = <String>[];
    changes.forEach((key, json) {
      if (json == null) {
        deletes.add(key);
      } else {
        puts[key] = jsonEncode(json);
      }
    });
    if (puts.isNotEmpty) await box.putAll(puts);
    if (deletes.isNotEmpty) await box.deleteAll(deletes);
  }

  @override
  Future<void> clearStorage() async {
    for (final b in _boxes.values) {
      await b.clear();
    }
  }

  @override
  Future<void> closeStorage() async {
    for (final b in _boxes.values) {
      await b.close();
    }
  }
}
