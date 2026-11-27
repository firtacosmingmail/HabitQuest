/** Projects resources: validation, mapping and routing (docs/PROJECTS.md). */
import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import { ApiError, mapDbError } from "../_shared/errors.ts";
import { withHttp } from "../_shared/http.ts";
import {
  consistentActionsSpec,
  goalsSpec,
  handleResource,
  planTasksSpec,
  projectsSpec,
  sessionMarksSpec,
  timeBlocksSpec,
} from "../_shared/resource.ts";
import {
  consistentActionToRow,
  goalToRow,
  planTaskToRow,
  projectToRow,
  rowToConsistentAction,
  rowToGoal,
  rowToPlanTask,
  rowToProject,
  rowToSessionMark,
  rowToTimeBlock,
  sessionMarkToRow,
  timeBlockToRow,
} from "../_shared/projects_mapping.ts";
import {
  parseSessionMarkId,
  sessionMarkId,
  validateConsistentAction,
  validateGoal,
  validatePlanTask,
  validateProject,
  validateRecurrence,
  validateSessionMark,
  validateTimeBlock,
} from "../_shared/projects_validation.ts";
import type {
  ConsistentAction,
  Goal,
  PlanTask,
  Project,
  SessionMark,
  TimeBlock,
} from "../_shared/types.ts";
import { MemoryStore, req } from "./fakes.ts";

const P = "7b0e1c2d-3e4f-4a5b-8c6d-7e8f9a0b1c2d";
const P2 = "7b0e1c2d-3e4f-4a5b-8c6d-000000000002";
const G = "c41a1c2d-3e4f-4a5b-8c6d-7e8f9a0b1c2d";
const K = "e9d21c2d-3e4f-4a5b-8c6d-7e8f9a0b1c2d";
const B = "5f3c1c2d-3e4f-4a5b-8c6d-7e8f9a0b1c2d";
const A = "a11c1c2d-3e4f-4a5b-8c6d-7e8f9a0b1c2d";
const created = "2026-11-01T08:00:00.000Z";
const updated = "2026-11-02T08:00:00.000Z";
const later = "2026-11-03T08:00:00.000Z";

export const projectBody = (o: Record<string, unknown> = {}) => ({
  id: P,
  name: "Content business",
  archived: false,
  createdAt: created,
  updatedAt: updated,
  deletedAt: null,
  ...o,
});
export const goalBody = (o: Record<string, unknown> = {}) => ({
  id: G,
  projectId: P,
  title: "5 videos",
  deadline: "2026-11-30",
  status: "inProgress" as const,
  createdAt: created,
  updatedAt: updated,
  deletedAt: null,
  ...o,
});
export const planTaskBody = (o: Record<string, unknown> = {}) => ({
  id: K,
  goalId: G,
  title: "5 scripts",
  deliveryDate: "2026-11-10",
  done: false,
  position: 0,
  createdAt: created,
  updatedAt: updated,
  deletedAt: null,
  ...o,
});
export const blockBody = (o: Record<string, unknown> = {}) => ({
  id: B,
  projectId: P,
  label: "Deep work",
  startTime: "10:00",
  endTime: "13:00",
  recurrence: { type: "weekly" as const, weekdays: [1, 2, 3, 4, 5] },
  startDate: null,
  endDate: null,
  createdAt: created,
  updatedAt: updated,
  deletedAt: null,
  ...o,
});
export const actionBody = (o: Record<string, unknown> = {}) => ({
  id: A,
  goalId: G,
  text: "Write 500 words",
  sortOrder: 0,
  createdAt: created,
  updatedAt: updated,
  deletedAt: null,
  ...o,
});
export const markBody = (o: Record<string, unknown> = {}) => ({
  timeBlockId: B,
  date: "2026-11-16",
  attended: true,
  updatedAt: updated,
  deletedAt: null,
  ...o,
});

function rejects(fn: () => unknown, fragment?: string) {
  const err = assertThrows(fn, ApiError);
  assertEquals(err.status, 400);
  assertEquals(err.code, "invalid_input");
  if (fragment) assert(err.message.includes(fragment), err.message);
}

// Validation ---------------------------------------------------------------

Deno.test("validateProject: contract JSON round-trips; defaults; ids lower-cased", () => {
  assertEquals(validateProject(projectBody()), projectBody());
  const minimal = validateProject({
    id: P.toUpperCase(),
    name: "X",
    createdAt: "2026-11-01T09:00:00+01:00",
    updatedAt: updated,
  });
  assertEquals(minimal.id, P);
  assertEquals(minimal.archived, false);
  assertEquals(minimal.deletedAt, null);
  assertEquals(minimal.createdAt, created);
  assertEquals(validateProject(projectBody({ id: undefined }), P.toUpperCase()).id, P);
});

Deno.test("validateProject rejects bad input", () => {
  rejects(() => validateProject([]), "JSON object");
  rejects(() => validateProject(projectBody({ id: "h1" })), "UUID");
  rejects(() => validateProject(projectBody({ id: undefined })), "id is required");
  rejects(() => validateProject(projectBody(), P2), "does not match");
  rejects(() => validateProject(projectBody(), "nope"), "UUID");
  rejects(() => validateProject(projectBody({ name: "  " })), "blank");
  rejects(() => validateProject(projectBody({ name: "x".repeat(201) })), "200");
  rejects(() => validateProject(projectBody({ archived: "no" })), "archived");
  rejects(() => validateProject(projectBody({ updatedAt: undefined })), "updatedAt");
  rejects(() => validateProject(projectBody({ createdAt: "2026-11-01" })), "createdAt");
  rejects(() => validateProject(projectBody({ deletedAt: 5 })), "deletedAt");
});

Deno.test("validateGoal: statuses, deadline, projectId", () => {
  assertEquals(validateGoal(goalBody()), goalBody());
  assertEquals(validateGoal(goalBody({ status: undefined })).status, "notStarted");
  for (const s of ["notStarted", "inProgress", "done"]) {
    assertEquals(validateGoal(goalBody({ status: s })).status, s);
  }
  assertEquals(validateGoal(goalBody({ projectId: P.toUpperCase() })).projectId, P);
  rejects(() => validateGoal([]), "Goal");
  rejects(() => validateGoal(goalBody({ status: "finished" })), "status");
  rejects(() => validateGoal(goalBody({ deadline: "2026-02-30" })), "deadline");
  rejects(() => validateGoal(goalBody({ deadline: null })), "deadline");
  rejects(() => validateGoal(goalBody({ projectId: "p1" })), "projectId");
  rejects(() => validateGoal(goalBody({ title: "" })), "title");
  rejects(() => validateGoal(goalBody({ title: "x".repeat(201) })), "200");
});

Deno.test("validatePlanTask: goalId, optional deliveryDate, defaults, position range", () => {
  assertEquals(validatePlanTask(planTaskBody()), planTaskBody());
  const t = validatePlanTask(
    planTaskBody({ deliveryDate: undefined, done: undefined, position: undefined }),
  );
  assertEquals([t.deliveryDate, t.done, t.position], [null, false, 0]);
  assertEquals(validatePlanTask(planTaskBody({ position: -3 })).position, -3);
  assertEquals(validatePlanTask(planTaskBody({ goalId: G.toUpperCase() })).goalId, G);
  rejects(() => validatePlanTask(planTaskBody({ position: 1.5 })), "position");
  rejects(() => validatePlanTask(planTaskBody({ position: 2 ** 31 })), "position");
  rejects(() => validatePlanTask(planTaskBody({ position: "1" })), "position");
  rejects(() => validatePlanTask(planTaskBody({ deliveryDate: "10/11/2026" })), "deliveryDate");
  rejects(() => validatePlanTask(planTaskBody({ done: 1 })), "done");
  rejects(() => validatePlanTask(planTaskBody({ goalId: undefined })), "goalId");
  // The old field name is not accepted any more.
  rejects(() => validatePlanTask(planTaskBody({ goalId: undefined, targetId: G })), "goalId");
});

Deno.test("validateRecurrence: weekly / monthly shapes", () => {
  assertEquals(validateRecurrence({ type: "weekly", weekdays: [1, 7] }), {
    type: "weekly",
    weekdays: [1, 7],
  });
  assertEquals(validateRecurrence({ type: "monthly", monthDays: [1, 15, 31], extra: 1 }), {
    type: "monthly",
    monthDays: [1, 15, 31],
  });
  rejects(() => validateRecurrence(null), "object");
  rejects(() => validateRecurrence({ type: "daily" }), "type");
  rejects(() => validateRecurrence({ type: "weekly", weekdays: [] }), "non-empty");
  rejects(() => validateRecurrence({ type: "weekly", weekdays: [0] }), "1..7");
  rejects(() => validateRecurrence({ type: "weekly", weekdays: [8] }), "1..7");
  rejects(() => validateRecurrence({ type: "weekly", weekdays: [2, 1] }), "sorted");
  rejects(() => validateRecurrence({ type: "weekly", weekdays: [1, 1] }), "duplicates");
  rejects(() => validateRecurrence({ type: "weekly", monthDays: [1] }), "weekdays");
  rejects(() => validateRecurrence({ type: "monthly", monthDays: [32] }), "1..31");
  rejects(() => validateRecurrence({ type: "monthly", monthDays: ["1"] }), "1..31");
});

Deno.test("validateTimeBlock: times, recurrence, label, start/end dates (no overlap check)", () => {
  assertEquals(validateTimeBlock(blockBody()), blockBody());
  assertEquals(validateTimeBlock(blockBody({ projectId: P.toUpperCase() })).projectId, P);
  // label: null / absent → null; stored as sent otherwise.
  assertEquals(validateTimeBlock(blockBody({ label: null })).label, null);
  assertEquals(validateTimeBlock(blockBody({ label: undefined })).label, null);
  assertEquals(validateTimeBlock(blockBody({ label: " Gym " })).label, " Gym ");
  assertEquals(validateTimeBlock(blockBody({ label: "x".repeat(200) })).label?.length, 200);
  rejects(() => validateTimeBlock(blockBody({ label: "" })), "label");
  rejects(() => validateTimeBlock(blockBody({ label: "   " })), "blank");
  rejects(() => validateTimeBlock(blockBody({ label: "x".repeat(201) })), "200");
  rejects(() => validateTimeBlock(blockBody({ label: 5 })), "label");
  // start / end dates: both optional, open-ended when endDate is null.
  const b = validateTimeBlock(blockBody({ startDate: "2026-11-05", endDate: undefined }));
  assertEquals([b.startDate, b.endDate], ["2026-11-05", null]);
  assertEquals(validateTimeBlock(blockBody({ endDate: "2026-12-31" })).endDate, "2026-12-31");
  assertEquals(
    validateTimeBlock(blockBody({ startDate: "2026-11-05", endDate: "2026-11-05" })).endDate,
    "2026-11-05",
  );
  rejects(
    () => validateTimeBlock(blockBody({ startDate: "2026-11-05", endDate: "2026-11-04" })),
    "endDate",
  );
  rejects(() => validateTimeBlock(blockBody({ endDate: "soon" })), "endDate");
  rejects(() => validateTimeBlock(blockBody({ startDate: "soon" })), "startDate");
  // times
  rejects(() => validateTimeBlock(blockBody({ startTime: "9:00" })), "startTime");
  rejects(() => validateTimeBlock(blockBody({ endTime: "24:00" })), "endTime");
  rejects(() => validateTimeBlock(blockBody({ endTime: "10:00" })), "after");
  rejects(() => validateTimeBlock(blockBody({ startTime: "23:00", endTime: "01:00" })), "after");
  rejects(() => validateTimeBlock(blockBody({ recurrence: undefined })), "recurrence");
  rejects(() => validateTimeBlock(blockBody({ projectId: undefined })), "projectId");
  rejects(() => validateTimeBlock([]), "TimeBlock");
});

Deno.test("validateConsistentAction: text, sortOrder, goalId", () => {
  assertEquals(validateConsistentAction(actionBody()), actionBody());
  assertEquals(validateConsistentAction(actionBody({ sortOrder: undefined })).sortOrder, 0);
  assertEquals(validateConsistentAction(actionBody({ sortOrder: -7 })).sortOrder, -7);
  assertEquals(
    validateConsistentAction(actionBody({ sortOrder: 2 ** 31 - 1 })).sortOrder,
    2 ** 31 - 1,
  );
  assertEquals(validateConsistentAction(actionBody({ goalId: G.toUpperCase() })).goalId, G);
  assertEquals(validateConsistentAction(actionBody({ text: "x".repeat(500) })).text.length, 500);
  assertEquals(validateConsistentAction(actionBody({ text: " a " })).text, " a ");
  rejects(() => validateConsistentAction(actionBody({ text: "x".repeat(501) })), "500");
  rejects(() => validateConsistentAction(actionBody({ text: "  " })), "blank");
  rejects(() => validateConsistentAction(actionBody({ text: undefined })), "text");
  rejects(() => validateConsistentAction(actionBody({ text: 1 })), "text");
  rejects(() => validateConsistentAction(actionBody({ sortOrder: 0.5 })), "sortOrder");
  rejects(() => validateConsistentAction(actionBody({ sortOrder: 2 ** 31 })), "sortOrder");
  rejects(() => validateConsistentAction(actionBody({ sortOrder: "1" })), "sortOrder");
  rejects(() => validateConsistentAction(actionBody({ goalId: "g1" })), "goalId");
  rejects(() => validateConsistentAction(actionBody({ createdAt: undefined })), "createdAt");
  rejects(() => validateConsistentAction(actionBody(), A.replace(/d$/, "e")), "does not match");
});

Deno.test("validateSessionMark: derived id, path id, mismatches", () => {
  const id = `${B}|2026-11-16`;
  assertEquals(validateSessionMark(markBody()), { id, ...markBody() });
  assertEquals(validateSessionMark(markBody({ id })).id, id);
  assertEquals(validateSessionMark(markBody(), `${B.toUpperCase()}|2026-11-16`).id, id);
  assertEquals(validateSessionMark(markBody({ timeBlockId: B.toUpperCase() })).timeBlockId, B);
  rejects(() => validateSessionMark(markBody(), `${B}|2026-11-17`), "expected");
  rejects(() => validateSessionMark(markBody({ id: `${B}_2026-11-16` })), "timeBlockId");
  rejects(() => validateSessionMark(markBody({ id: 7 })), "string");
  rejects(() => validateSessionMark(markBody({ attended: undefined })), "attended");
  rejects(() => validateSessionMark(markBody({ date: "2026-13-01" })), "date");
  rejects(() => validateSessionMark(markBody({ timeBlockId: "a1" })), "timeBlockId");
  rejects(
    () => validateSessionMark(markBody({ timeBlockId: undefined, actionId: B })),
    "timeBlockId",
  );
});

Deno.test("session mark ids", () => {
  assertEquals(sessionMarkId(B.toUpperCase(), "2026-11-16"), `${B}|2026-11-16`);
  assertEquals(parseSessionMarkId(`${B}|2026-11-16`), { timeBlockId: B, date: "2026-11-16" });
  rejects(() => parseSessionMarkId(B));
  rejects(() => parseSessionMarkId(`${B}|2026-02-30`));
  rejects(() => parseSessionMarkId(`x|2026-11-16`));
});

// Mapping ------------------------------------------------------------------

Deno.test("mapping: rows from Postgres (to_jsonb) → contract JSON", () => {
  const pgTs = "2026-11-02T08:00:00+00:00";
  const pgCreated = "2026-11-01T08:00:00.123456+00:00";
  assertEquals(
    rowToProject({
      user_id: "u",
      id: P,
      name: "Content business",
      archived: false,
      created_at: pgCreated,
      updated_at: pgTs,
      deleted_at: null,
      server_updated_at: pgTs,
    }),
    projectBody({ createdAt: "2026-11-01T08:00:00.123Z" }),
  );
  assertEquals(
    rowToGoal({
      id: G,
      project_id: P,
      title: "5 videos",
      deadline: "2026-11-30",
      status: "inProgress" as const,
      created_at: created,
      updated_at: pgTs,
      deleted_at: "2026-11-05T10:00:00+00:00",
    }),
    goalBody({ deletedAt: "2026-11-05T10:00:00.000Z" }),
  );
  assertEquals(
    rowToPlanTask({
      id: K,
      goal_id: G,
      title: "5 scripts",
      delivery_date: "2026-11-10",
      done: false,
      position: 0,
      created_at: created,
      updated_at: pgTs,
      deleted_at: null,
    }),
    planTaskBody(),
  );
  assertEquals(
    rowToTimeBlock({
      user_id: "u",
      id: B,
      project_id: P,
      label: "Deep work",
      start_time: "10:00",
      end_time: "13:00",
      recurrence: { type: "weekly" as const, weekdays: [1, 2, 3, 4, 5] },
      start_date: "2026-11-02",
      end_date: "2026-12-31",
      created_at: created,
      updated_at: pgTs,
      deleted_at: null,
      server_updated_at: pgTs,
    }),
    blockBody({ startDate: "2026-11-02", endDate: "2026-12-31" }),
  );
  assertEquals(
    rowToTimeBlock({
      id: B,
      project_id: P,
      label: null,
      start_time: "10:00",
      end_time: "13:00",
      recurrence: { type: "weekly" as const, weekdays: [1, 2, 3, 4, 5] },
      start_date: null,
      end_date: null,
      created_at: created,
      updated_at: pgTs,
      deleted_at: null,
    }),
    blockBody({ label: null }),
  );
  assertEquals(
    rowToConsistentAction({
      user_id: "u",
      id: A,
      goal_id: G,
      text: "Write 500 words",
      sort_order: 0,
      created_at: created,
      updated_at: pgTs,
      deleted_at: null,
      server_updated_at: pgTs,
    }),
    actionBody(),
  );
  assertEquals(
    rowToSessionMark({
      time_block_id: B,
      date: "2026-11-16",
      attended: true,
      updated_at: pgTs,
      deleted_at: null,
    }),
    { id: `${B}|2026-11-16`, ...markBody() },
  );
});

Deno.test("mapping: contract JSON → snake_case rows round-trip", () => {
  const p = validateProject(projectBody());
  assertEquals(rowToProject(projectToRow(p)), p);
  assertEquals(projectToRow(p).created_at, created);
  const g = validateGoal(goalBody());
  assertEquals(goalToRow(g).project_id, P);
  assertEquals(rowToGoal(goalToRow(g)), g);
  const k = validatePlanTask(planTaskBody());
  assertEquals(planTaskToRow(k).delivery_date, "2026-11-10");
  assertEquals(planTaskToRow(k).goal_id, G);
  assertEquals(rowToPlanTask(planTaskToRow(k)), k);
  const b = validateTimeBlock(blockBody({ startDate: "2026-11-02", endDate: "2026-11-30" }));
  assertEquals(timeBlockToRow(b), {
    id: B,
    project_id: P,
    label: "Deep work",
    start_time: "10:00",
    end_time: "13:00",
    recurrence: { type: "weekly", weekdays: [1, 2, 3, 4, 5] },
    start_date: "2026-11-02",
    end_date: "2026-11-30",
    created_at: created,
    updated_at: updated,
    deleted_at: null,
  });
  assertEquals(rowToTimeBlock(timeBlockToRow(b)), b);
  const open = validateTimeBlock(blockBody({ label: null }));
  assertEquals([timeBlockToRow(open).label, timeBlockToRow(open).end_date], [null, null]);
  assertEquals(rowToTimeBlock(timeBlockToRow(open)), open);
  const a = validateConsistentAction(actionBody({ sortOrder: 3 }));
  assertEquals(consistentActionToRow(a), {
    id: A,
    goal_id: G,
    text: "Write 500 words",
    sort_order: 3,
    created_at: created,
    updated_at: updated,
    deleted_at: null,
  });
  assertEquals(rowToConsistentAction(consistentActionToRow(a)), a);
  const m = validateSessionMark(markBody());
  assertEquals(sessionMarkToRow(m), {
    time_block_id: B,
    date: "2026-11-16",
    attended: true,
    updated_at: updated,
    deleted_at: null,
  });
  assertEquals(rowToSessionMark(sessionMarkToRow(m)), m);
});

Deno.test("mapDbError: foreign key → the resource's parent_not_found", () => {
  const fk = new ApiError(409, "parent_not_found", "push the project first");
  assertEquals(mapDbError({ code: "23503" }, fk), fk);
  assertEquals(mapDbError({ code: "23503" }).code, "habit_not_found");
  assertEquals(mapDbError({ code: "23514" }, fk).code, "invalid_input");
});

// Routing ------------------------------------------------------------------

function mustExist<P extends { id: string; updatedAt: string; deletedAt: string | null }>(
  parents: MemoryStore<P>,
  parent: string,
  key: (c: never) => string,
) {
  return (item: unknown) => {
    if (!parents.rows.has(key(item as never))) {
      throw new ApiError(409, "parent_not_found", `${parent} missing`);
    }
  };
}

function setup() {
  const projects = new MemoryStore<Project>();
  const goals = new MemoryStore<Goal>(
    mustExist(projects, "project", (g: Goal) => g.projectId),
    (g) => g.projectId,
  );
  const blocks = new MemoryStore<TimeBlock>(
    mustExist(projects, "project", (b: TimeBlock) => b.projectId),
    (b) => b.projectId,
  );
  const tasks = new MemoryStore<PlanTask>(
    mustExist(goals, "goal", (k: PlanTask) => k.goalId),
    (k) => k.goalId,
  );
  const actions = new MemoryStore<ConsistentAction>(
    mustExist(goals, "goal", (a: ConsistentAction) => a.goalId),
    (a) => a.goalId,
  );
  const marks = new MemoryStore<SessionMark>(
    mustExist(blocks, "time block", (m: SessionMark) => m.timeBlockId),
    (m) => m.timeBlockId,
  );
  return {
    projects,
    actions,
    marks,
    p: withHttp((r) => handleResource(r, projectsSpec, projects)),
    g: withHttp((r) => handleResource(r, goalsSpec, goals)),
    b: withHttp((r) => handleResource(r, timeBlocksSpec, blocks)),
    k: withHttp((r) => handleResource(r, planTasksSpec, tasks)),
    a: withHttp((r) => handleResource(r, consistentActionsSpec, actions)),
    m: withHttp((r) => handleResource(r, sessionMarksSpec, marks)),
  };
}

Deno.test("projects: PUT/GET/LWW/DELETE/delta pull", async () => {
  const { p, projects } = setup();
  let res = await p(req("PUT", `projects/${P}`, projectBody()));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { item: projectBody(), applied: true });

  res = await p(req("PUT", `projects/${P}`, projectBody({ name: "old", updatedAt: created })));
  let body = await res.json();
  assertEquals([body.applied, body.item.name], [false, "Content business"]);
  res = await p(req("PUT", `projects/${P}`, projectBody({ name: "same" })));
  assertEquals((await res.json()).applied, false);

  res = await p(req("GET", `projects/${P.toUpperCase()}`));
  assertEquals((await res.json()).id, P);
  res = await p(req("GET", `projects/${P2}`));
  assertEquals([res.status, (await res.json()).error.code], [404, "not_found"]);
  res = await p(req("GET", "projects/not-a-uuid"));
  assertEquals(res.status, 400);

  const cursor = new Date(projects.clock).toISOString();
  await p(req("POST", "projects", projectBody({ id: P2 })));
  res = await p(req("DELETE", `projects/${P}?updatedAt=${later}`));
  body = await res.json();
  assertEquals([body.applied, body.item.deletedAt, body.item.updatedAt], [true, later, later]);
  res = await p(req("DELETE", `projects/${P}?updatedAt=${updated}`));
  assertEquals((await res.json()).applied, false);
  res = await p(req("DELETE", `projects/${P2.replace(/2$/, "3")}`));
  assertEquals(res.status, 404);

  res = await p(req("GET", `projects?since=${encodeURIComponent(cursor)}`));
  const delta = await res.json();
  assertEquals(delta.items.map((i: Project) => i.id), [P2, P]);
  assertEquals(typeof delta.serverTime, "string");
});

Deno.test("projects: batch, invalid batch writes nothing, routes and methods", async () => {
  const { p, projects } = setup();
  let res = await p(req("POST", "projects/batch", {
    items: [projectBody(), projectBody({ id: P2, name: "" })],
  }));
  assertEquals(res.status, 400);
  assert((await res.json()).error.message.startsWith("items[1]"));
  assertEquals(projects.rows.size, 0);

  res = await p(req("POST", "projects/batch", { items: [projectBody(), projectBody({ id: P2 })] }));
  const { results } = await res.json();
  assertEquals(results.map((r: { id: string; applied: boolean }) => [r.id, r.applied]), [
    [P, true],
    [P2, true],
  ]);

  assertEquals((await p(req("PUT", `projects/${P}`, projectBody({ id: P2 })))).status, 400);
  assertEquals((await p(req("GET", `projects/${P}/x`))).status, 404);
  assertEquals((await p(req("PATCH", `projects/${P}`, projectBody()))).status, 405);
  assertEquals((await p(req("DELETE", "projects"))).status, 405);
  assertEquals((await p(req("OPTIONS", "projects"))).status, 200);
});

Deno.test("goals and time blocks need their project; projectId filters", async () => {
  const { p, g, b } = setup();
  let res = await g(req("PUT", `goals/${G}`, goalBody()));
  assertEquals([res.status, (await res.json()).error.code], [409, "parent_not_found"]);
  res = await b(req("PUT", `time-blocks/${B}`, blockBody()));
  assertEquals([res.status, (await res.json()).error.code], [409, "parent_not_found"]);

  await p(req("PUT", `projects/${P}`, projectBody()));
  await p(req("PUT", `projects/${P2}`, projectBody({ id: P2 })));
  res = await g(req("PUT", `goals/${G}`, goalBody()));
  assertEquals(await res.json(), { item: goalBody(), applied: true });
  const G2 = G.replace(/d$/, "e");
  await g(req("POST", "goals", goalBody({ id: G2, projectId: P2 })));
  res = await g(req("GET", `goals?projectId=${P2.toUpperCase()}`));
  assertEquals((await res.json()).items.map((i: Goal) => i.id), [G2]);
  assertEquals((await g(req("GET", "goals?projectId=bad"))).status, 400);

  res = await b(req("POST", "time-blocks/batch", { items: [blockBody()] }));
  assertEquals((await res.json()).results[0].item, blockBody());
  const B2 = B.replace(/d$/, "e");
  res = await b(req("PUT", `time-blocks/${B2}`, blockBody({ id: B2, projectId: P2, label: null })));
  assertEquals((await res.json()).item.label, null);
  res = await b(req("PUT", `time-blocks/${B}`, blockBody({ endTime: "09:00" })));
  assertEquals(res.status, 400);
  res = await b(req(
    "PUT",
    `time-blocks/${B}`,
    blockBody({
      startDate: "2026-11-10",
      endDate: "2026-11-09",
      updatedAt: later,
    }),
  ));
  assertEquals(res.status, 400);
  res = await b(
    req("PUT", `time-blocks/${B}`, blockBody({ endDate: "2026-12-31", updatedAt: later })),
  );
  assertEquals((await res.json()).item.endDate, "2026-12-31");
  res = await b(req("GET", `time-blocks?projectId=${P}`));
  assertEquals((await res.json()).items.map((i: TimeBlock) => i.id), [B]);
  assertEquals((await b(req("GET", "time-blocks?projectId=bad"))).status, 400);
  res = await b(req("GET", `time-blocks/${B.toUpperCase()}`));
  assertEquals((await res.json()).endDate, "2026-12-31");
  res = await b(req("DELETE", `time-blocks/${B2}?updatedAt=${later}`));
  assertEquals((await res.json()).item.deletedAt, later);
});

Deno.test("plan tasks and consistent actions need their goal; goalId filters", async () => {
  const { p, g, k, a, actions } = setup();
  await p(req("PUT", `projects/${P}`, projectBody()));
  let res = await k(req("PUT", `plan-tasks/${K}`, planTaskBody()));
  assertEquals([res.status, (await res.json()).error.code], [409, "parent_not_found"]);
  res = await a(req("PUT", `consistent-actions/${A}`, actionBody()));
  assertEquals([res.status, (await res.json()).error.code], [409, "parent_not_found"]);

  await g(req("PUT", `goals/${G}`, goalBody()));
  res = await k(req("PUT", `plan-tasks/${K}`, planTaskBody()));
  assertEquals(await res.json(), { item: planTaskBody(), applied: true });
  res = await k(req("GET", `plan-tasks?goalId=${G}`));
  assertEquals((await res.json()).items.length, 1);
  res = await k(req("GET", `plan-tasks?goalId=${G.replace(/d$/, "e")}`));
  assertEquals((await res.json()).items, []);
  assertEquals((await k(req("GET", "plan-tasks?goalId=x"))).status, 400);

  const A2 = A.replace(/d$/, "e");
  res = await a(req("POST", "consistent-actions/batch", {
    items: [actionBody(), actionBody({ id: A2, text: "Edit one video", sortOrder: 1 })],
  }));
  const { results } = await res.json();
  assertEquals(results.map((r: { id: string }) => r.id), [A, A2]);
  assertEquals(results[0].item, actionBody());
  res = await a(req("POST", "consistent-actions/batch", {
    items: [actionBody({ updatedAt: later }), actionBody({ id: A2, text: "" })],
  }));
  assertEquals(res.status, 400);
  assertEquals(actions.rows.get(A)?.item.updatedAt, updated); // nothing written
  res = await a(
    req("PUT", `consistent-actions/${A}`, actionBody({ text: "older", updatedAt: created })),
  );
  assertEquals((await res.json()).applied, false);
  res = await a(req("GET", `consistent-actions?goalId=${G.toUpperCase()}`));
  assertEquals((await res.json()).items.map((i: ConsistentAction) => i.id), [A, A2]);
  assertEquals((await a(req("GET", "consistent-actions?goalId=x"))).status, 400);
  res = await a(req("DELETE", `consistent-actions/${A2}?updatedAt=${later}`));
  const del = await res.json();
  assertEquals([del.applied, del.item.deletedAt, del.item.text], [true, later, "Edit one video"]);
  assertEquals((await a(req("GET", `consistent-actions/${A}`))).status, 200);
});

Deno.test("session-marks: composite id in the path, LWW un-mark, tombstone", async () => {
  const { p, b, m, marks } = setup();
  await p(req("PUT", `projects/${P}`, projectBody()));
  let res = await m(req("POST", "session-marks", markBody()));
  assertEquals((await res.json()).error.code, "parent_not_found");
  await b(req("PUT", `time-blocks/${B}`, blockBody()));
  const id = `${B}|2026-11-16`;
  const path = `session-marks/${encodeURIComponent(id)}`;

  res = await m(req("PUT", `session-marks/${B}%7C2026-11-16`, markBody({ timeBlockId: P })));
  assertEquals(res.status, 400); // path id does not match the body
  res = await m(req("PUT", path, markBody()));
  assertEquals(await res.json(), { item: { id, ...markBody() }, applied: true });
  assert(marks.rows.has(id));

  res = await m(req("POST", "session-marks/batch", {
    items: [markBody({ attended: false, updatedAt: later }), markBody({ date: "2026-11-17" })],
  }));
  const { results } = await res.json();
  assertEquals(results.map((r: { id: string }) => r.id), [id, `${B}|2026-11-17`]);
  assertEquals(results[0].item.attended, false);

  res = await m(req("GET", `session-marks/${B.toUpperCase()}%7C2026-11-16`));
  assertEquals((await res.json()).attended, false);
  res = await m(req("GET", `session-marks/${B}%7C2026-11-18`));
  assertEquals(res.status, 404);
  res = await m(req("GET", `session-marks/${B}_2026-11-16`));
  assertEquals(res.status, 400);

  res = await m(req("GET", `session-marks?timeBlockId=${B}`));
  assertEquals((await res.json()).items.length, 2);
  res = await m(req("GET", `session-marks?timeBlockId=${P}`));
  assertEquals((await res.json()).items.length, 0);
  assertEquals((await m(req("GET", "session-marks?timeBlockId=x"))).status, 400);

  const at = "2026-11-20T00:00:00.000Z";
  res = await m(req("DELETE", `${path}?updatedAt=${at}`));
  const del = await res.json();
  assertEquals([del.applied, del.item.deletedAt, del.item.id], [true, at, id]);
});
