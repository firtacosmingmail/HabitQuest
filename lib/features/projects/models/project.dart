import 'json.dart';

/// A user's project (e.g. "Content business"). Owns [Target]s.
///
/// Immutable; use [copyWith] and `ProjectService` to persist changes.
/// Sync metadata ([updatedAt], [deletedAt]) follows the habit rules:
/// last-write-wins on [updatedAt], soft delete via [deletedAt].
class Project {
  /// UUID v4.
  final String id;
  final String name;
  final bool archived;

  /// Creation time (UTC).
  final DateTime createdAt;

  /// Last local or remote change (UTC). Drives last-write-wins sync.
  final DateTime updatedAt;

  /// Tombstone (UTC); `null` when alive.
  final DateTime? deletedAt;

  Project({
    required this.id,
    required this.name,
    this.archived = false,
    required DateTime createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  })  : createdAt = createdAt.toUtc(),
        updatedAt = (updatedAt ?? createdAt).toUtc(),
        deletedAt = deletedAt?.toUtc();

  bool get isDeleted => deletedAt != null;

  Project copyWith({
    String? name,
    bool? archived,
    DateTime? updatedAt,
    DateTime? Function()? deletedAt,
  }) =>
      Project(
        id: id,
        name: name ?? this.name,
        archived: archived ?? this.archived,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'archived': archived,
        'createdAt': formatTimestamp(createdAt),
        'updatedAt': formatTimestamp(updatedAt),
        'deletedAt': formatOptionalTimestamp(deletedAt),
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        name: json['name'] as String,
        archived: json['archived'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: parseOptionalTimestamp(json['updatedAt']),
        deletedAt: parseOptionalTimestamp(json['deletedAt']),
      );

  /// Content equality; [updatedAt] is sync metadata and not compared.
  @override
  bool operator ==(Object other) =>
      other is Project &&
      other.id == id &&
      other.name == name &&
      other.archived == archived &&
      other.createdAt == createdAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(id, name, archived, createdAt, deletedAt);

  @override
  String toString() =>
      'Project($id, $name${archived ? ', archived' : ''}'
      '${isDeleted ? ', deleted' : ''})';
}
