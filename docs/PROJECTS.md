# Projects: data model, contract and rules

The foundation of the Projects feature (`lib/features/projects/`). The UI,
backend/sync, notifications, calendar and XP tasks build on this document,
the models and the providers listed below. Treat the field names, JSON
shapes and rules here as the **contract**: change them only together with
every consumer.

A user has any number of **projects**. A project has **targets**. A target
has a title, a deadline, a manual status, a **plan** (tasks) and
**consistent actions** (recurring time blocks). The occurrences of the
consistent actions are **sessions**; the user can mark a session attended.

Example: project "Content business" → target "5 videos", deadline 30 Nov,
plan "5 scripts", "5 recordings", "5 edits", consistent action Mon–Fri
10:00–13:00.

## Folder

```
lib/features/projects/
  models/
    project.dart            Project
    target.dart             Target, TargetStatus
    plan_task.dart          PlanTask
    consistent_action.dart  ConsistentAction, sealed ActionRecurrence (WeeklyRecurrence, MonthlyRecurrence)
    clock_time.dart         ClockTime (local wall-clock "HH:mm")
    session_mark.dart       SessionMark (the stored "attended" mark)
    session.dart            Session (computed occurrence, never stored)
    projects_data.dart      ProjectsData (immutable snapshot of visible records)
  domain/
    sessions.dart           sessionDates, hasSessionOn, expandSessions, sessionsInRange, compareSessions
    overlap.dart            timesOverlap, firstOverlapDate, findActionClashes, ActionClash,
                            ActionOverlapException, describeRecurrence, ordinal
    project_events.dart     ProjectChangeEvent, ProjectChangeType, SessionAttendanceEvent
    project_service.dart    ProjectService (every mutation + event streams)
  data/
    project_repository.dart ProjectRepository, CachedProjectRepository, InMemoryProjectRepository,
                            ProjectRecords, ProjectEntityKind
    hive_project_repository.dart HiveProjectRepository
  projects_providers.dart   Riverpod providers
```

`domain/` and `models/` are pure Dart (no Flutter imports).

## Data model

Common to every record (same rules as the synced habit entities):

| Field | Type | Notes |
|---|---|---|
| `id` | UUID v4 string | Generated on the device (`ProjectService`). Not on `SessionMark` (see below). |
| `createdAt` | UTC timestamp | Not on `SessionMark`. |
| `updatedAt` | UTC timestamp | Last local or remote change. **Last-write-wins** key. Every local write stamps a strictly newer value (`nextStamp`). Defaults to `createdAt` when missing. |
| `deletedAt` | UTC timestamp or `null` | Soft delete (tombstone). Tombstones are kept for sync and hidden everywhere else. |

Deleting a parent tombstones its children in the same write (project →
targets → plan tasks + consistent actions). Visibility also cascades on
read: a record whose parent (or grand-parent) is deleted or unknown is
hidden even if its own `deletedAt` is `null` (so a remote parent tombstone
that arrives before its children is enough). Session marks are never
tombstoned locally; they are hidden with their action.

### Project

| Field | Type | Notes |
|---|---|---|
| `name` | string | Non-empty (trimmed). |
| `archived` | bool | Default `false`. Archived projects stay visible to the data layer (filter in the UI); their actions still have sessions and still count for overlaps. |

### Target

| Field | Type | Notes |
|---|---|---|
| `projectId` | UUID | Owning project. Cannot change. |
| `title` | string | Non-empty (trimmed). |
| `deadline` | date `yyyy-MM-dd` | Local calendar day. Sessions run up to and **including** it. |
| `status` | `"notStarted"` \| `"inProgress"` \| `"done"` | **Set by the user only.** The app never derives or changes it (not from the plan, the sessions or the deadline). Unknown values read as `notStarted`. |

### PlanTask

| Field | Type | Notes |
|---|---|---|
| `targetId` | UUID | Owning target. Cannot change. |
| `title` | string | Non-empty (trimmed). |
| `deliveryDate` | date `yyyy-MM-dd` or `null` | Optional. |
| `done` | bool | Checked off by the user. |
| `position` | int | Sort order within the plan (ascending, ties by `createdAt`, `id`). New tasks are appended (`last + 1`). |

Plan progress (`done / total`) is for display only.

### ConsistentAction

| Field | Type | Notes |
|---|---|---|
| `targetId` | UUID | Owning target. Cannot change. |
| `startTime` | `"HH:mm"` | Local wall-clock time, 24 h. |
| `endTime` | `"HH:mm"` | Must be **after** `startTime` (strictly). No blocks across midnight: split them into two actions. |
| `recurrence` | object | `{"type": "weekly", "weekdays": [1,2,3,4,5]}` (ISO 1 = Mon … 7 = Sun) **or** `{"type": "monthly", "monthDays": [1, 15]}` (1 … 31). Non-empty, sorted ascending, no duplicates. Unknown `type` is a format error. |
| `startDate` | date `yyyy-MM-dd` or `null` | Optional first day. `null` = the local calendar day of `createdAt`. |

### SessionMark

The user's "attended" mark on one session. Identified by
**`(actionId, date)`**, not by a UUID (like habit check-ins: two devices
marking the same session converge on one record). Local key and sync
queue id: `"<actionId>|yyyy-MM-dd"`.

| Field | Type | Notes |
|---|---|---|
| `actionId` | UUID | The consistent action. |
| `date` | date `yyyy-MM-dd` | The session's day. |
| `attended` | bool | Un-marking keeps the record with `attended: false` and a fresh `updatedAt`, so the un-mark syncs. |
| `updatedAt` | UTC timestamp | LWW. |
| `deletedAt` | UTC timestamp or `null` | Only from the server. |

Only dates on which the action has a session, and not in the future, can
be marked (`ProjectService.setSessionAttended`).

## JSON shape (storage and sync contract)

The local Hive JSON (`toJson()` / `fromJson()`) **is** the wire shape:
camelCase keys, timestamps as ISO-8601 UTC strings with `Z`
(`2026-11-01T08:00:00.000Z`), dates as `yyyy-MM-dd`, times as `HH:mm`.
`null` fields are sent as `null`. Readers must tolerate a missing
`updatedAt` (→ `createdAt`), `deletedAt` / `startDate` / `deliveryDate`
(→ `null`), `archived` / `done` (→ `false`), `position` (→ `0`).

```jsonc
// Project
{ "id": "7b0e…", "name": "Content business", "archived": false,
  "createdAt": "2026-11-01T08:00:00.000Z", "updatedAt": "2026-11-01T08:00:00.000Z",
  "deletedAt": null }

// Target
{ "id": "c41a…", "projectId": "7b0e…", "title": "5 videos",
  "deadline": "2026-11-30", "status": "inProgress",
  "createdAt": "…Z", "updatedAt": "…Z", "deletedAt": null }

// PlanTask
{ "id": "e9d2…", "targetId": "c41a…", "title": "5 scripts",
  "deliveryDate": "2026-11-10", "done": false, "position": 0,
  "createdAt": "…Z", "updatedAt": "…Z", "deletedAt": null }

// ConsistentAction
{ "id": "5f3c…", "targetId": "c41a…", "startTime": "10:00", "endTime": "13:00",
  "recurrence": { "type": "weekly", "weekdays": [1, 2, 3, 4, 5] },
  "startDate": null,
  "createdAt": "…Z", "updatedAt": "…Z", "deletedAt": null }

// SessionMark
{ "actionId": "5f3c…", "date": "2026-11-16", "attended": true,
  "updatedAt": "…Z", "deletedAt": null }
```

Notes for the backend task: rows are per user (RLS on `auth.uid()`);
`SessionMark` has the composite primary key `(user_id, action_id, date)`;
the server resolves conflicts by `updatedAt` (newer wins, as for habits
and check-ins) and should store `recurrence` as JSON (validate its shape).
The server does **not** enforce the overlap rule (it is a client save
rule; merged data from two offline devices may contain a clash, which the
client tolerates: see "Overlap").

## Recurrence rules (sessions)

`domain/sessions.dart`. A consistent action has a session on calendar day
`d` iff

1. `action.effectiveStartDate <= d <= target.deadline` (both inclusive;
   `effectiveStartDate` = `startDate`, else the local day of `createdAt`),
2. weekly: `d.weekday ∈ weekdays`; monthly: `d.day ∈ monthDays`.

* **Missing month days**: a month without the day has **no session** for
  it that month (the 31st in April, June, September, November; the 29th
  and 30th in February, the 29th only exists in leap years). No shifting
  to the last day of the month.
* **Wall-clock times**: a session is `startTime`–`endTime` on its day, in
  local time. Days are iterated with `addDays` (calendar days), so DST
  changes never move, drop or duplicate a session. `Session.start` /
  `Session.end` build `DateTime(y, m, d, h, min)`; on a "spring forward"
  day a time inside the skipped hour is moved forward by the platform
  (e.g. 02:30 → 03:30).
* **No midnight crossing**: `endTime > startTime` is enforced by the
  `ConsistentAction` constructor (`ArgumentError`).
* **Deadline cut-off**: no session after the deadline; the deadline day
  itself has one if it matches. A start date after the deadline means no
  sessions at all (allowed).
* Done targets and archived projects still have sessions (the providers /
  `sessionsInRange` include them; filter with `includeDoneTargets` /
  `includeArchivedProjects`).

```dart
List<DateTime> sessionDates(ConsistentAction a, {required DateTime deadline, required DateTime from, required DateTime to})
bool hasSessionOn(ConsistentAction a, {required DateTime deadline, required DateTime date})
List<Session> expandSessions(ConsistentAction a, Target t, {required DateTime from, required DateTime to, bool Function(String actionId, DateTime date)? attended})
List<Session> sessionsInRange(ProjectsData data, {required DateTime from, required DateTime to, bool includeDoneTargets = true, bool includeArchivedProjects = true})
```

`from` / `to` are inclusive and normalised to dates. Results are sorted by
date, start time, end time, action id.

## Overlap rule

`domain/overlap.dart`. Two consistent actions **overlap** iff there is a
calendar day on which **both** have a session (rules above, each with its
own target's deadline) **and** their wall-clock intervals intersect:
`aStart < bEnd && bStart < aEnd` (half-open `[start, end)`). Touching ends
(10:00–13:00 and 13:00–15:00) do **not** overlap. Any project counts,
including the same target.

Ignored: the action itself (same `id`), deleted actions, actions of deleted
targets / projects, and actions of targets marked **done** (also: when the
candidate's own target is done, it clashes with nothing).

```dart
bool timesOverlap(ClockTime aStart, ClockTime aEnd, ClockTime bStart, ClockTime bEnd)
DateTime? firstOverlapDate(ConsistentAction a, DateTime aDeadline, ConsistentAction b, DateTime bDeadline)
List<ActionClash> findActionClashes(ConsistentAction candidate, Target candidateTarget, ProjectsData data)
class ActionClash { ConsistentAction action; Target target; Project? project; DateTime firstDate; String describe(); }
class ActionOverlapException { ConsistentAction action; List<ActionClash> clashes; String get message; }
```

`findActionClashes` returns every clashing action with its target, project
and **first clash date**, sorted by that date. Pass the candidate target as
it will be saved (an edited deadline counts).

**Saving is blocked** (`ProjectService` throws `ActionOverlapException`,
nothing is written, no event):

* `createAction` / `updateAction` when the action clashes with anything;
* `updateTarget` / `setTargetStatus` when the change (a later deadline, or
  a status moved away from done) makes one of its actions clash with an
  action it did not clash with before.

`ActionOverlapException.message` is a ready English message, e.g.
`This time block (Tue, Thu 12:30–13:30) overlaps "5 videos" (Content business), Mon–Fri 10:00–13:00, first on 2026-11-17`.
The UI can build its own copy from `clashes` (`target.title`,
`project?.name`, `describeRecurrence(action.recurrence)`,
`action.startTime`–`action.endTime`, `firstDate`). For live form
validation call `ProjectService.clashesFor(action, target: edited)`.

## ProjectService

Use it (via `projectServiceProvider`) for **every** mutation.

```dart
// Projects
Future<Project> createProject({required String name})
Future<Project> updateProject(Project edited)          // emits updated / archived / unarchived
Future<Project> renameProject(String id, String name)
Future<Project> archiveProject(String id, {bool archived = true})
Future<void>    deleteProject(String id)               // cascades
// Targets
Future<Target> createTarget({required String projectId, required String title, required DateTime deadline, TargetStatus status = TargetStatus.notStarted})
Future<Target> updateTarget(Target edited)             // may throw ActionOverlapException
Future<Target> setTargetStatus(String id, TargetStatus status)
Future<void>   deleteTarget(String id)                 // cascades
// Plan
Future<PlanTask> addPlanTask({required String targetId, required String title, DateTime? deliveryDate})
Future<PlanTask> updatePlanTask(PlanTask edited)
Future<PlanTask> setPlanTaskDone(String id, bool done)
Future<void>     reorderPlanTasks(String targetId, List<String> orderedIds)
Future<void>     deletePlanTask(String id)
// Consistent actions
List<ActionClash>        clashesFor(ConsistentAction action, {Target? target})
Future<ConsistentAction> createAction({required String targetId, required ClockTime startTime, required ClockTime endTime, required ActionRecurrence recurrence, DateTime? startDate})
Future<ConsistentAction> updateAction(ConsistentAction edited)
Future<void>             deleteAction(String id)
// Sessions
bool         isAttended(String actionId, DateTime date)
Future<void> setSessionAttended(String actionId, DateTime date, bool attended)
Future<bool> toggleSessionAttended(String actionId, DateTime date)
// Sync / maintenance
Future<void> applyRemote(ProjectRecords records)       // no local events, no attendance events
Future<void> clearLocalData()                          // announced on remoteChanges as deletions
ProjectsData get data;  DateTime get today;
Stream<ProjectChangeEvent>     changes           // local
Stream<ProjectChangeEvent>     remoteChanges     // sync / wipe
Stream<SessionAttendanceEvent> attendanceEvents  // user marks (XP)
```

* Unknown or deleted ids → `StateError`. Empty names/titles, an end not
  after the start, a future or non-session date to mark, a changed parent
  id → `ArgumentError`. Clashes → `ActionOverlapException`.
* Events fire **after** the write; nothing changed → no event.
* `ProjectChangeEvent {type, kind, record, previous}`: `kind` is a
  `ProjectEntityKind` (`project`, `target`, `planTask`, `consistentAction`;
  never `sessionMark`), `record` the saved record (typed getters
  `project`, `target`, `planTask`, `action`, and `id`). A cascade delete
  emits one `deleted` event per record, children first.
* `SessionAttendanceEvent {actionId, targetId, projectId, date, attended}`
  for XP (like `CompletionEvent`). Never emitted for synced data.
* XP: the `GameEngine` listens to `changes` (plan task `done`, target
  `status`, deletions; compares `previous` with `record`) and
  `attendanceEvents`. Amounts and keys: README "Game rules" → Projects XP.
  The sync task must pass the pulled records to
  `GameEngine.reconcileSynced(appliedProjects: …)` (README "How XP stays
  consistent").

## Providers (`projects_providers.dart`)

| Provider | Type |
|---|---|
| `projectRepositoryProvider` | `Provider<ProjectRepository>`: **must be overridden** (`main.dart`: `HiveProjectRepository`; tests: `InMemoryProjectRepository`, done by `pumpHabitQuestApp` / `wrapForTest`, param `projectRepository:`) |
| `projectServiceProvider` | `Provider<ProjectService>` (uses `clockProvider`) |
| `projectsDataProvider` | `StreamProvider<ProjectsData>` |
| `projectsProvider` / `activeProjectsProvider` / `archivedProjectsProvider` | `Provider<AsyncValue<List<Project>>>` |
| `projectByIdProvider(id)` | `Provider<AsyncValue<Project?>>` |
| `targetsOfProjectProvider(projectId)` | `Provider<AsyncValue<List<Target>>>` |
| `targetByIdProvider(id)` | `Provider<AsyncValue<Target?>>` |
| `planTasksOfTargetProvider(targetId)` | `Provider<AsyncValue<List<PlanTask>>>` |
| `planProgressProvider(targetId)` | `Provider<({int done, int total})>` (display only) |
| `actionsOfTargetProvider(targetId)` | `Provider<AsyncValue<List<ConsistentAction>>>` |
| `sessionsProvider((from:, to:, projectId:, targetId:))` | `Provider<AsyncValue<List<Session>>>`: pass `dateOnly` bounds; `projectId` / `targetId` may be `null` |
| `todaySessionsProvider` | `Provider<AsyncValue<List<Session>>>` |
| `projectChangesProvider` / `remoteProjectChangesProvider` | `Provider<Stream<ProjectChangeEvent>>` |
| `sessionAttendanceEventsProvider` | `Provider<Stream<SessionAttendanceEvent>>` |

## Storage

`HiveProjectRepository`: five `Box<String>` boxes of JSON, no adapters.

| Box | Key | Value |
|---|---|---|
| `projects` | `id` | `Project` |
| `project_targets` | `id` | `Target` |
| `project_plan_tasks` | `id` | `PlanTask` |
| `project_actions` | `id` | `ConsistentAction` |
| `project_session_marks` | `actionId\|yyyy-MM-dd` | `SessionMark` |

Tombstones are stored. Unreadable entries are skipped (logged). All
records are cached in memory; `watchData()` emits the current snapshot on
listen, then once per write batch.

## Sync

Wired like habits (README "Sync"):

* `main.dart` opens `HiveProjectRepository.open(recorder: queue)`, so every
  local write is queued (ids; session marks by key `actionId|yyyy-MM-dd`).
* `SyncEngine` pushes the five kinds parent-first through the Projects
  Edge Functions (`HabitQuestApi.*ProjectRecord*`, `ProjectResource`), pulls
  each since its own cursor, resolves LWW against `get*Record()` and applies
  the winners with `ProjectService.applyRemote(ProjectRecords(...))`, which
  announces them on `remoteChanges` (UI, notifications, calendar). The pulled
  records go to `GameEngine.reconcileSynced(appliedProjects: …)`.
* First sign-in claim records every `getAll*Records()` entry; an account
  switch and account deletion (`LocalDataWiper`) call
  `ProjectService.clearLocalData()`.
