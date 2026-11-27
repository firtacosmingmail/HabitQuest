# Projects: data model, contract and rules

The data layer of the Projects feature (`lib/features/projects/`). The UI,
backend/sync, notifications, calendar and XP build on this document, the
models and the providers listed below. Treat the field names, JSON shapes
and rules here as the **contract**: change them only together with every
consumer (the app, `supabase/functions`, `supabase/API.md`).

A user has any number of **projects**. A project has **goals** and **time
blocks**.

* A **goal** has a title, a deadline, a manual status, a **plan** (tasks)
  and **consistent actions** (plain text items: what you keep doing to get
  there).
* A **time block** is a recurring block of work of the project (start and
  end time, days of the week or days of the month, optional start date,
  optional end date, optional label). Its occurrences are **sessions**; the
  user can mark a session attended.

Example: project "Content business" → goal "5 videos", deadline 30 Nov,
plan "5 scripts", "5 recordings", "5 edits", consistent actions "Post one
short a day", "Reply to comments"; time block "Editing", Mon–Fri
10:00–13:00, ongoing.

> **History.** Until the rework of November 2026 goals were called
> **targets**, and "consistent actions" were the recurring time blocks of a
> target (cut off at its deadline). Ids were kept: a goal has its old target
> id and a time block its old consistent-action id. See "Local data
> migration" and "XP ledger keys".

## Folder

```
lib/features/projects/
  models/
    project.dart            Project
    goal.dart               Goal, GoalStatus
    plan_task.dart          PlanTask
    consistent_action.dart  ConsistentAction (text item of a goal)
    time_block.dart         TimeBlock, sealed BlockRecurrence (WeeklyRecurrence, MonthlyRecurrence)
    clock_time.dart         ClockTime (local wall-clock "HH:mm")
    session_mark.dart       SessionMark (the stored "attended" mark)
    session.dart            Session (computed occurrence, never stored)
    projects_data.dart      ProjectsData (immutable snapshot of visible records)
  domain/
    sessions.dart           sessionDates, hasSessionOn, expandSessions, sessionsInRange, compareSessions
    overlap.dart            timesOverlap, firstOverlapDate, firstCommonDay, findTimeBlockClashes,
                            TimeBlockClash, TimeBlockOverlapException, describeRecurrence, ordinal
    project_events.dart     ProjectChangeEvent, ProjectChangeType, SessionAttendanceEvent
    project_service.dart    ProjectService (every mutation + event streams)
  data/
    project_repository.dart ProjectRepository, CachedProjectRepository, InMemoryProjectRepository,
                            ProjectRecords, ProjectEntityKind
    hive_project_repository.dart HiveProjectRepository
    projects_storage_migration.dart migrateProjectsStorage, migrateHiveProjectsStorage (v1 → v2)
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

The tree:

```
Project ─┬─ Goal ─┬─ PlanTask
         │        └─ ConsistentAction
         └─ TimeBlock ── SessionMark
```

Deleting a parent tombstones its children in the same write (project →
goals → plan tasks + consistent actions; project → time blocks). Visibility
also cascades on read: a record whose parent (or grand-parent) is deleted or
unknown is hidden even if its own `deletedAt` is `null` (so a remote parent
tombstone that arrives before its children is enough). Session marks are
never tombstoned locally; they are hidden with their time block.

### Project

| Field | Type | Notes |
|---|---|---|
| `name` | string | Non-empty (trimmed). |
| `archived` | bool | Default `false`. Archived projects stay visible to the data layer (filter in the UI); their time blocks still have sessions and still count for overlaps. |

### Goal

| Field | Type | Notes |
|---|---|---|
| `projectId` | UUID | Owning project. Cannot change. |
| `title` | string | Non-empty (trimmed). |
| `deadline` | date `yyyy-MM-dd` | Local calendar day. For display and reminders; it does **not** cut off the project's time blocks. |
| `status` | `"notStarted"` \| `"inProgress"` \| `"done"` | **Set by the user only.** The app never derives or changes it. Unknown values read as `notStarted`. |

### PlanTask

| Field | Type | Notes |
|---|---|---|
| `goalId` | UUID | Owning goal. Cannot change. |
| `title` | string | Non-empty (trimmed). |
| `deliveryDate` | date `yyyy-MM-dd` or `null` | Optional. |
| `done` | bool | Checked off by the user. |
| `position` | int | Sort order within the plan (ascending, ties by `createdAt`, `id`). New tasks are appended (`last + 1`). |

Plan progress (`done / total`) is for display only.

### ConsistentAction (text item of a goal)

| Field | Type | Notes |
|---|---|---|
| `goalId` | UUID | Owning goal. Cannot change. |
| `text` | string | Non-empty (trimmed by the app; the server accepts ≤ 500 characters). |
| `sortOrder` | int (32-bit) | Sort order within the goal (ascending, ties by `createdAt`, `id`). New items are appended (`last + 1`); `reorderConsistentActions` renumbers `0…n-1`. Missing → `0`. |

No time, no tick-off, no XP.

### TimeBlock (of a project)

| Field | Type | Notes |
|---|---|---|
| `projectId` | UUID | Owning project. Cannot change. |
| `label` | string or `null` | Optional (e.g. "Editing"). Trimmed; blank → `null`. Shown with (or instead of) the project name. Server: ≤ 200 characters. |
| `startTime` | `"HH:mm"` | Local wall-clock time, 24 h. |
| `endTime` | `"HH:mm"` | Must be **after** `startTime` (strictly). No blocks across midnight: split them into two blocks. |
| `recurrence` | object | `{"type": "weekly", "weekdays": [1,2,3,4,5]}` (ISO 1 = Mon … 7 = Sun) **or** `{"type": "monthly", "monthDays": [1, 15]}` (1 … 31). Non-empty, sorted ascending, no duplicates. Unknown `type` is a format error. |
| `startDate` | date `yyyy-MM-dd` or `null` | Optional first day. `null` = the local calendar day of `createdAt`. |
| `endDate` | date `yyyy-MM-dd` or `null` | Optional last day (inclusive). `null` = **open-ended** (ongoing). Must not be before `startDate` when both are set (`ArgumentError` / server `400`). |

### SessionMark

The user's "attended" mark on one session. Identified by
**`(timeBlockId, date)`**, not by a UUID (like habit check-ins: two devices
marking the same session converge on one record). Local key and sync queue
id: `"<timeBlockId>|yyyy-MM-dd"`.

| Field | Type | Notes |
|---|---|---|
| `timeBlockId` | UUID | The time block. |
| `date` | date `yyyy-MM-dd` | The session's day. |
| `attended` | bool | Un-marking keeps the record with `attended: false` and a fresh `updatedAt`, so the un-mark syncs. |
| `updatedAt` | UTC timestamp | LWW. |
| `deletedAt` | UTC timestamp or `null` | Only from the server. |

Only dates on which the block has a session, and not in the future, can be
marked (`ProjectService.setSessionAttended`).

## JSON shape (storage and sync contract)

The local Hive JSON (`toJson()` / `fromJson()`) **is** the wire shape:
camelCase keys, timestamps as ISO-8601 UTC strings with `Z`
(`2026-11-01T08:00:00.000Z`), dates as `yyyy-MM-dd`, times as `HH:mm`.
`null` fields are sent as `null`. Readers must tolerate a missing
`updatedAt` (→ `createdAt`), `deletedAt` / `startDate` / `endDate` /
`label` / `deliveryDate` (→ `null`), `archived` / `done` (→ `false`),
`position` / `sortOrder` (→ `0`).

```jsonc
// Project
{ "id": "7b0e…", "name": "Content business", "archived": false,
  "createdAt": "2026-11-01T08:00:00.000Z", "updatedAt": "2026-11-01T08:00:00.000Z",
  "deletedAt": null }

// Goal
{ "id": "c41a…", "projectId": "7b0e…", "title": "5 videos",
  "deadline": "2026-11-30", "status": "inProgress",
  "createdAt": "…Z", "updatedAt": "…Z", "deletedAt": null }

// PlanTask
{ "id": "e9d2…", "goalId": "c41a…", "title": "5 scripts",
  "deliveryDate": "2026-11-10", "done": false, "position": 0,
  "createdAt": "…Z", "updatedAt": "…Z", "deletedAt": null }

// ConsistentAction
{ "id": "a71f…", "goalId": "c41a…", "text": "Post one short a day", "sortOrder": 0,
  "createdAt": "…Z", "updatedAt": "…Z", "deletedAt": null }

// TimeBlock
{ "id": "5f3c…", "projectId": "7b0e…", "label": "Editing",
  "startTime": "10:00", "endTime": "13:00",
  "recurrence": { "type": "weekly", "weekdays": [1, 2, 3, 4, 5] },
  "startDate": null, "endDate": null,
  "createdAt": "…Z", "updatedAt": "…Z", "deletedAt": null }

// SessionMark
{ "timeBlockId": "5f3c…", "date": "2026-11-16", "attended": true,
  "updatedAt": "…Z", "deletedAt": null }
```

Backend (`supabase/migrations/20261127120000_goals_time_blocks.sql`,
`supabase/API.md` "Projects"): rows are per user (RLS on `auth.uid()`);
tables `projects`, `goals`, `plan_tasks` (`goal_id`), `time_blocks`
(`project_id`, `label`, `end_date`), `consistent_actions` (`goal_id`,
`text`, `sort_order`) and `session_marks` (composite primary key
`(user_id, time_block_id, date)`). The server resolves conflicts by
`updatedAt` (newer wins) and validates `recurrence`. It does **not** enforce
the overlap rule (a client save rule; merged data from two offline devices
may contain a clash, which the client tolerates: see "Overlap").

Edge Functions, in parent-first push order: `projects`, `goals`
(`?projectId=`), `time-blocks` (`?projectId=`), `plan-tasks` (`?goalId=`),
`consistent-actions` (`?goalId=`), `session-marks` (`?timeBlockId=`, path id
`<timeBlockId>|<date>`). The old `targets` function is removed.

## Recurrence rules (sessions)

`domain/sessions.dart`. A time block has a session on calendar day `d` iff

1. `block.effectiveStartDate <= d` and (`endDate == null` or
   `d <= endDate`) (inclusive; `effectiveStartDate` = `startDate`, else the
   local day of `createdAt`),
2. weekly: `d.weekday ∈ weekdays`; monthly: `d.day ∈ monthDays`.

* **Open-ended**: a block without an end date has sessions forever; every
  caller passes a bounded `[from, to]` range (the calendar week, the
  notification window, the details screen's recent / upcoming days).
* **Missing month days**: a month without the day has **no session** for
  it that month (the 31st in April, June, September, November; the 29th
  and 30th in February, the 29th only exists in leap years). No shifting
  to the last day of the month.
* **Wall-clock times**: a session is `startTime`–`endTime` on its day, in
  local time. Days are iterated with `addDays` (calendar days), so DST
  changes never move, drop or duplicate a session. `Session.start` /
  `Session.end` build `DateTime(y, m, d, h, min)`; on a "spring forward"
  day a time inside the skipped hour is moved forward by the platform.
* **No midnight crossing**: `endTime > startTime` is enforced by the
  `TimeBlock` constructor (`ArgumentError`).
* Goal deadlines and statuses do not affect sessions. Archived projects
  still have sessions (filter with `includeArchivedProjects: false`).

```dart
List<DateTime> sessionDates(TimeBlock b, {required DateTime from, required DateTime to})
bool hasSessionOn(TimeBlock b, {required DateTime date})
List<Session> expandSessions(TimeBlock b, {required DateTime from, required DateTime to, bool Function(String timeBlockId, DateTime date)? attended})
List<Session> sessionsInRange(ProjectsData data, {required DateTime from, required DateTime to, bool includeArchivedProjects = true})
class Session { String timeBlockId; String projectId; String? label; DateTime date; ClockTime startTime, endTime; bool attended; }
```

`from` / `to` are inclusive and normalised to dates. Results are sorted by
date, start time, end time, block id.

## Overlap rule

`domain/overlap.dart`. Two time blocks **overlap** iff there is a calendar
day on which **both** have a session (rules above) **and** their wall-clock
intervals intersect: `aStart < bEnd && bStart < aEnd` (half-open
`[start, end)`). Touching ends (10:00–13:00 and 13:00–15:00) do **not**
overlap. **All** time blocks of **all** projects count, including the same
project and archived projects. Ignored: the block itself (same `id`),
deleted blocks and blocks of deleted projects.

**Open-ended blocks are checked exactly**, by periodicity, never with a
short look-ahead (`firstCommonDay`):

* weekly × weekly repeats every 7 days, so the 7 days from the common start
  decide (disjoint weekdays → never);
* monthly × monthly: the shared month days are checked month by month
  (shared days only in short months, e.g. the 31st, are found in the next
  month that has them; no shared day → never);
* weekly × monthly: month by month, each candidate month day is matched
  against its weekday;
* the month scan stops at the common end date, or after one full Gregorian
  cycle (400 years = 146 097 days = 20 871 weeks, after which weekdays and
  month days repeat exactly), so "never" is a proven answer, not a guess.
  In practice the first clash is found within a few months.

A randomized test compares it against a day-by-day reference scan.

```dart
bool timesOverlap(ClockTime aStart, ClockTime aEnd, ClockTime bStart, ClockTime bEnd)
DateTime? firstOverlapDate(TimeBlock a, TimeBlock b)
DateTime? firstCommonDay(BlockRecurrence a, BlockRecurrence b, {required DateTime from, DateTime? to})
List<TimeBlockClash> findTimeBlockClashes(TimeBlock candidate, ProjectsData data)
class TimeBlockClash { TimeBlock block; Project? project; DateTime firstDate; String describe(); }
class TimeBlockOverlapException { TimeBlock block; List<TimeBlockClash> clashes; String get message; }
```

`findTimeBlockClashes` returns every clashing block with its project and
**first clash date**, sorted by that date, then project name.

**Saving is blocked**: `createTimeBlock` / `updateTimeBlock` throw
`TimeBlockOverlapException` when the block clashes with anything; nothing
is written, no event. Goal changes never clash (goals have no times).

`TimeBlockOverlapException.message` is a ready English message naming the
project, the label and the times, e.g.
`This time block (Tue, Thu 12:30–13:30) overlaps "Content business" (Editing), Mon–Fri 10:00–13:00, first on 2026-11-17`
(without a label: `… overlaps "Fitness", Mon 10:00–13:00, first on …`).
The UI can build its own copy from `clashes` (`project?.name`,
`block.label`, `describeRecurrence(block.recurrence)`,
`block.startTime`–`block.endTime`, `firstDate`). For live form validation
call `ProjectService.clashesFor(block)`.

## ProjectService

Use it (via `projectServiceProvider`) for **every** mutation.

```dart
// Projects
Future<Project> createProject({required String name})
Future<Project> updateProject(Project edited)          // emits updated / archived / unarchived
Future<Project> renameProject(String id, String name)
Future<Project> archiveProject(String id, {bool archived = true})
Future<void>    deleteProject(String id)               // cascades: goals (+ plan, actions), time blocks
// Goals
Future<Goal> createGoal({required String projectId, required String title, required DateTime deadline, GoalStatus status = GoalStatus.notStarted})
Future<Goal> updateGoal(Goal edited)
Future<Goal> setGoalStatus(String id, GoalStatus status)
Future<void> deleteGoal(String id)                     // cascades: plan tasks, consistent actions
// Plan
Future<PlanTask> addPlanTask({required String goalId, required String title, DateTime? deliveryDate})
Future<PlanTask> updatePlanTask(PlanTask edited)
Future<PlanTask> setPlanTaskDone(String id, bool done)
Future<void>     reorderPlanTasks(String goalId, List<String> orderedIds)
Future<void>     deletePlanTask(String id)
// Consistent actions (text items of a goal)
Future<ConsistentAction> addConsistentAction({required String goalId, required String text})
Future<ConsistentAction> updateConsistentAction(ConsistentAction edited)
Future<ConsistentAction> editConsistentAction(String id, String text)
Future<void>             reorderConsistentActions(String goalId, List<String> orderedIds)
Future<void>             deleteConsistentAction(String id)
// Time blocks (of a project)
List<TimeBlockClash> clashesFor(TimeBlock block)
Future<TimeBlock>    createTimeBlock({required String projectId, String? label, required ClockTime startTime, required ClockTime endTime, required BlockRecurrence recurrence, DateTime? startDate, DateTime? endDate})
Future<TimeBlock>    updateTimeBlock(TimeBlock edited)
Future<void>         deleteTimeBlock(String id)
// Sessions
bool         isAttended(String timeBlockId, DateTime date)
Future<void> setSessionAttended(String timeBlockId, DateTime date, bool attended)
Future<bool> toggleSessionAttended(String timeBlockId, DateTime date)
// Sync / maintenance
Future<void> applyRemote(ProjectRecords records)       // no local events, no attendance events
Future<void> clearLocalData()                          // announced on remoteChanges as deletions
ProjectsData get data;  DateTime get today;
Stream<ProjectChangeEvent>     changes           // local
Stream<ProjectChangeEvent>     remoteChanges     // sync / wipe
Stream<SessionAttendanceEvent> attendanceEvents  // user marks (XP)
```

* Unknown or deleted ids → `StateError`. Empty names/titles/texts, an end
  not after the start, an end date before the start date, a future or
  non-session date to mark, a changed parent id, a reorder list that is not
  exactly the goal's ids → `ArgumentError`. Clashes →
  `TimeBlockOverlapException`.
* Events fire **after** the write; nothing changed → no event. A reorder
  stamps and emits only the items whose order changed.
* `ProjectChangeEvent {type, kind, record, previous}`: `kind` is a
  `ProjectEntityKind` (`project`, `goal`, `planTask`, `timeBlock`,
  `consistentAction`; `sessionMark` only on `remoteChanges`), `record` the
  saved record (typed getters `project`, `goal`, `planTask`, `timeBlock`,
  `consistentAction`, and `id`). A cascade delete emits one `deleted` event
  per record, children first (time blocks, consistent actions, plan tasks,
  goals, project).
* `SessionAttendanceEvent {timeBlockId, projectId, date, attended}` for XP
  (like `CompletionEvent`). Never emitted for synced data.

## XP ledger keys

The `GameEngine` listens to `changes` (plan task `done`, goal `status`,
deletions; compares `previous` with `record`) and `attendanceEvents`.
Amounts are unchanged (README "Game rules" → Projects XP): plan task done
10, session attended 15 (project time blocks), goal done 50. Keys in
`GameState.projectLedger`:

| Grant | Key | Note |
|---|---|---|
| Plan task done | `task:<planTaskId>` | unchanged |
| Session attended | `session:<timeBlockId>\|yyyy-MM-dd` | a time block keeps its old consistent-action id, so old keys still match |
| Goal done | `target:<goalId>` (`GameState.goalKey`) | **legacy prefix kept on purpose**: goal ids are the old target ids, so ledgers written before the rework (locally and in the synced `game_state`) stay valid without a migration |

The achievement ids `first_target_done` and `targets_5` are kept for the
same reason (`AchievementIds.firstGoalDone` / `goals5`). Deleting a time
block (or its project) takes back the XP of its sessions; deleting a goal
takes back its plan task and goal grants. The sync engine passes the pulled
records to `GameEngine.reconcileSynced(appliedProjects: …)` (README "How XP
stays consistent").

## Providers (`projects_providers.dart`)

| Provider | Type |
|---|---|
| `projectRepositoryProvider` | `Provider<ProjectRepository>`: **must be overridden** (`main.dart`: `HiveProjectRepository`; tests: `InMemoryProjectRepository`, done by `pumpHabitQuestApp` / `wrapForTest`, param `projectRepository:`) |
| `projectServiceProvider` | `Provider<ProjectService>` (uses `clockProvider`) |
| `projectsDataProvider` | `StreamProvider<ProjectsData>` |
| `projectsProvider` / `activeProjectsProvider` / `archivedProjectsProvider` | `Provider<AsyncValue<List<Project>>>` |
| `projectByIdProvider(id)` | `Provider<AsyncValue<Project?>>` |
| `goalsOfProjectProvider(projectId)` | `Provider<AsyncValue<List<Goal>>>` |
| `goalByIdProvider(id)` | `Provider<AsyncValue<Goal?>>` |
| `planTasksOfGoalProvider(goalId)` | `Provider<AsyncValue<List<PlanTask>>>` |
| `planProgressProvider(goalId)` | `Provider<({int done, int total})>` (display only) |
| `consistentActionsOfGoalProvider(goalId)` | `Provider<AsyncValue<List<ConsistentAction>>>` (by `sortOrder`) |
| `timeBlocksOfProjectProvider(projectId)` | `Provider<AsyncValue<List<TimeBlock>>>` |
| `timeBlockByIdProvider(id)` | `Provider<AsyncValue<TimeBlock?>>` |
| `sessionsProvider((from:, to:, projectId:, timeBlockId:))` | `Provider<AsyncValue<List<Session>>>`: pass `dateOnly` bounds; `projectId` / `timeBlockId` may be `null` |
| `todaySessionsProvider` | `Provider<AsyncValue<List<Session>>>` |
| `projectChangesProvider` / `remoteProjectChangesProvider` | `Provider<Stream<ProjectChangeEvent>>` |
| `sessionAttendanceEventsProvider` | `Provider<Stream<SessionAttendanceEvent>>` |

## Storage

`HiveProjectRepository`: six `Box<String>` boxes of JSON, no adapters.

| Box | Key | Value |
|---|---|---|
| `projects` | `id` | `Project` |
| `project_goals` | `id` | `Goal` |
| `project_plan_tasks` | `id` | `PlanTask` |
| `project_time_blocks` | `id` | `TimeBlock` |
| `project_consistent_actions` | `id` | `ConsistentAction` |
| `project_session_marks` | `timeBlockId\|yyyy-MM-dd` | `SessionMark` |
| `projects_meta` | `schemaVersion` | `"2"` (local schema marker) |

Tombstones are stored. Unreadable entries are skipped (logged). All
records are cached in memory; `watchData()` emits the current snapshot on
listen, then once per write batch.

## Local data migration (schema v1 → v2)

`data/projects_storage_migration.dart`, run by `main.dart`
(`migrateHiveProjectsStorage`) **before** the sync queue and the repository
load. It works on raw JSON through `StringStore`s (tested in memory and
with Hive):

1. `project_targets` → `project_goals` (same JSON, same ids).
2. `project_actions` (consistent actions of a target) →
   `project_time_blocks`: `projectId` = the target's project, `label` = the
   target's title, `endDate` = `null` (open-ended; no more deadline
   cut-off). A block whose target was deleted inherits the target's
   `deletedAt` (it would otherwise come back to life now that it hangs off
   the project). `updatedAt` is kept, so the result equals the server
   migration's and sync sees no conflict. Blocks of unknown targets are
   dropped (they were already hidden).
3. `project_plan_tasks`: `targetId` → `goalId`; `project_session_marks`:
   `actionId` → `timeBlockId` (keys unchanged, so attended marks and their
   XP stay attached).
4. `sync_queue`: pending `target:<id>` entries become `goal:<id>`,
   `consistentAction:<id>` (old meaning) become `timeBlock:<id>`.
5. `sync_meta`: every Projects pull cursor is deleted (all users on the
   device), so the next sync is a full pull of the renamed resources.
6. The old boxes are emptied and deleted; `projects_meta.schemaVersion` =
   `2` is written **last**.

Idempotent: the marker skips it afterwards (which also keeps new-meaning
`consistentAction` queue entries from being renamed), and every step is
safe to re-run after a crash before the marker (copies are written before
the old entries are removed).

## Sync

Wired like habits (README "Sync"):

* `main.dart` opens `HiveProjectRepository.open(recorder: queue)`, so every
  local write is queued (ids; session marks by key `timeBlockId|yyyy-MM-dd`).
* `SyncEngine` pushes the six kinds parent-first (`ProjectResource` order:
  projects → goals, time blocks → plan tasks, consistent actions, session
  marks) through the Projects Edge Functions (`HabitQuestApi.*ProjectRecord*`),
  pulls each since its own cursor (`<function>Cursor:<userId>` in
  `sync_meta`), resolves LWW against `get*Record()` and applies the winners
  with `ProjectService.applyRemote(ProjectRecords(...))`, which announces
  them on `remoteChanges` (UI, notifications, calendar). The pulled records
  go to `GameEngine.reconcileSynced(appliedProjects: …)`.
* First sign-in claim records every `getAll*Records()` entry; an account
  switch and account deletion (`LocalDataWiper`) call
  `ProjectService.clearLocalData()`.

## Notifications and calendar (data side)

* Work split notifications fire at the start of each session of every
  (non-archived) project's time blocks, open-ended ones included, within the
  rolling window; the copy uses the block label, else the project name.
  Goal deadline reminders (3 days, 1 day, morning) and plan task deliveries
  skip goals marked done.
* The work split calendar shows every block's sessions coloured per project
  and labelled with the block label (else the project name); goal deadlines
  are flags. Tapping a block opens the session sheet (mark attended, open
  the project).
