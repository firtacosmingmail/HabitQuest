/** Projects resources: validation, mapping and routing (docs/PROJECTS.md). */
import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import { ApiError, mapDbError } from "../_shared/errors.ts";
import { withHttp } from "../_shared/http.ts";
import {
  consistentActionsSpec,
  handleResource,
  planTasksSpec,
  projectsSpec,
  sessionMarksSpec,
  targetsSpec,
} from "../_shared/resource.ts";
import {
  consistentActionToRow,
  planTaskToRow,
  projectToRow,
  rowToConsistentAction,
  rowToPlanTask,
  rowToProject,
  rowToSessionMark,
  rowToTarget,
  sessionMarkToRow,
  targetToRow,
} from "../_shared/projects_mapping.ts";
import {
  parseSessionMarkId,
  sessionMarkId,
  validateConsistentAction,
  validatePlanTask,
  validateProject,
  validateRecurrence,
  validateSessionMark,
  validateTarget,
} from "../_shared/projects_validation.ts";
import type { ConsistentAction, PlanTask, Project, SessionMark, Target } from "../_shared/types.ts";
import { MemoryStore, req } from "./fakes.ts";

const P = "7b0e1c2d-3e4f-4a5b-8c6d-7e8f9a0b1c2d";
const P2 = "7b0e1c2d-3e4f-4a5b-8c6d-000000000002";
const T = "c41a1c2d-3e4f-4a5b-8c6d-7e8f9a0b1c2d";
const K = "e9d21c2d-3e4f-4a5b-8c6d-7e8f9a0b1c2d";
const A = "5f3c1c2d-3e4f-4a5b-8c6d-7e8f9a0b1c2d";
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
export const targetBody = (o: Record<string, unknown> = {}) => ({
  id: T,
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
  targetId: T,
  title: "5 scripts",
  deliveryDate: "2026-11-10",
  done: false,
  position: 0,
  createdAt: created,
  updatedAt: updated,
  deletedAt: null,
  ...o,
});
export const actionBody = (o: Record<string, unknown> = {}) => ({
  id: A,
  targetId: T,
  startTime: "10:00",
  endTime: "13:00",
  recurrence: { type: "weekly" as const, weekdays: [1, 2, 3, 4, 5] },
  startDate: null,
  createdAt: created,
  updatedAt: updated,
  deletedAt: null,
  ...o,
});
export const markBody = (o: Record<string, unknown> = {}) => ({
  actionId: A,
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

Deno.test("validateTarget: statuses, deadline, projectId", () => {
  assertEquals(validateTarget(targetBody()), targetBody());
  assertEquals(validateTarget(targetBody({ status: undefined })).status, "notStarted");
  for (const s of ["notStarted", "inProgress", "done"]) {
    assertEquals(validateTarget(targetBody({ status: s })).status, s);
  }
  assertEquals(validateTarget(targetBody({ projectId: P.toUpperCase() })).projectId, P);
  rejects(() => validateTarget(targetBody({ status: "finished" })), "status");
  rejects(() => validateTarget(targetBody({ deadline: "2026-02-30" })), "deadline");
  rejects(() => validateTarget(targetBody({ deadline: null })), "deadline");
  rejects(() => validateTarget(targetBody({ projectId: "p1" })), "projectId");
  rejects(() => validateTarget(targetBody({ title: "" })), "title");
});

Deno.test("validatePlanTask: optional deliveryDate, defaults, position range", () => {
  assertEquals(validatePlanTask(planTaskBody()), planTaskBody());
  const t = validatePlanTask(
    planTaskBody({ deliveryDate: undefined, done: undefined, position: undefined }),
  );
  assertEquals([t.deliveryDate, t.done, t.position], [null, false, 0]);
  assertEquals(validatePlanTask(planTaskBody({ position: -3 })).position, -3);
  rejects(() => validatePlanTask(planTaskBody({ position: 1.5 })), "position");
  rejects(() => validatePlanTask(planTaskBody({ position: 2 ** 31 })), "position");
  rejects(() => validatePlanTask(planTaskBody({ position: "1" })), "position");
  rejects(() => validatePlanTask(planTaskBody({ deliveryDate: "10/11/2026" })), "deliveryDate");
  rejects(() => validatePlanTask(planTaskBody({ done: 1 })), "done");
  rejects(() => validatePlanTask(planTaskBody({ targetId: undefined })), "targetId");
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

Deno.test("validateConsistentAction: times, recurrence, startDate (no overlap check)", () => {
  assertEquals(validateConsistentAction(actionBody()), actionBody());
  assertEquals(
    validateConsistentAction(actionBody({ startDate: "2026-11-05" })).startDate,
    "2026-11-05",
  );
  assertEquals(validateConsistentAction(actionBody({ startDate: undefined })).startDate, null);
  rejects(() => validateConsistentAction(actionBody({ startTime: "9:00" })), "startTime");
  rejects(() => validateConsistentAction(actionBody({ endTime: "24:00" })), "endTime");
  rejects(() => validateConsistentAction(actionBody({ endTime: "10:00" })), "after");
  rejects(
    () => validateConsistentAction(actionBody({ startTime: "23:00", endTime: "01:00" })),
    "after",
  );
  rejects(() => validateConsistentAction(actionBody({ recurrence: undefined })), "recurrence");
  rejects(() => validateConsistentAction(actionBody({ startDate: "soon" })), "startDate");
});

Deno.test("validateSessionMark: derived id, path id, mismatches", () => {
  const id = `${A}|2026-11-16`;
  assertEquals(validateSessionMark(markBody()), { id, ...markBody() });
  assertEquals(validateSessionMark(markBody({ id })).id, id);
  assertEquals(validateSessionMark(markBody(), `${A.toUpperCase()}|2026-11-16`).id, id);
  assertEquals(validateSessionMark(markBody({ actionId: A.toUpperCase() })).actionId, A);
  rejects(() => validateSessionMark(markBody(), `${A}|2026-11-17`), "expected");
  rejects(() => validateSessionMark(markBody({ id: `${A}_2026-11-16` })), "actionId");
  rejects(() => validateSessionMark(markBody({ id: 7 })), "string");
  rejects(() => validateSessionMark(markBody({ attended: undefined })), "attended");
  rejects(() => validateSessionMark(markBody({ date: "2026-13-01" })), "date");
  rejects(() => validateSessionMark(markBody({ actionId: "a1" })), "actionId");
});

Deno.test("session mark ids", () => {
  assertEquals(sessionMarkId(A.toUpperCase(), "2026-11-16"), `${A}|2026-11-16`);
  assertEquals(parseSessionMarkId(`${A}|2026-11-16`), { actionId: A, date: "2026-11-16" });
  rejects(() => parseSessionMarkId(A));
  rejects(() => parseSessionMarkId(`${A}|2026-02-30`));
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
    rowToTarget({
      id: T,
      project_id: P,
      title: "5 videos",
      deadline: "2026-11-30",
      status: "inProgress" as const,
      created_at: created,
      updated_at: pgTs,
      deleted_at: "2026-11-05T10:00:00+00:00",
    }),
    targetBody({ deletedAt: "2026-11-05T10:00:00.000Z" }),
  );
  assertEquals(
    rowToPlanTask({
      id: K,
      target_id: T,
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
    rowToConsistentAction({
      id: A,
      target_id: T,
      start_time: "10:00",
      end_time: "13:00",
      recurrence: { type: "weekly" as const, weekdays: [1, 2, 3, 4, 5] },
      start_date: null,
      created_at: created,
      updated_at: pgTs,
      deleted_at: null,
    }),
    actionBody(),
  );
  assertEquals(
    rowToSessionMark({
      action_id: A,
      date: "2026-11-16",
      attended: true,
      updated_at: pgTs,
      deleted_at: null,
    }),
    { id: `${A}|2026-11-16`, ...markBody() },
  );
});

Deno.test("mapping: contract JSON → snake_case rows round-trip", () => {
  const p = validateProject(projectBody());
  assertEquals(rowToProject(projectToRow(p)), p);
  assertEquals(projectToRow(p).created_at, created);
  const t = validateTarget(targetBody());
  assertEquals(targetToRow(t).project_id, P);
  assertEquals(rowToTarget(targetToRow(t)), t);
  const k = validatePlanTask(planTaskBody());
  assertEquals(planTaskToRow(k).delivery_date, "2026-11-10");
  assertEquals(rowToPlanTask(planTaskToRow(k)), k);
  const a = validateConsistentAction(actionBody({ startDate: "2026-11-02" }));
  assertEquals(consistentActionToRow(a).start_time, "10:00");
  assertEquals(rowToConsistentAction(consistentActionToRow(a)), a);
  const m = validateSessionMark(markBody());
  assertEquals(sessionMarkToRow(m), {
    action_id: A,
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
  const targets = new MemoryStore<Target>(
    mustExist(projects, "project", (t: Target) => t.projectId),
    (t) => t.projectId,
  );
  const tasks = new MemoryStore<PlanTask>(
    mustExist(targets, "target", (k: PlanTask) => k.targetId),
    (k) => k.targetId,
  );
  const actions = new MemoryStore<ConsistentAction>(
    mustExist(targets, "target", (a: ConsistentAction) => a.targetId),
    (a) => a.targetId,
  );
  const marks = new MemoryStore<SessionMark>(
    mustExist(actions, "action", (m: SessionMark) => m.actionId),
    (m) => m.actionId,
  );
  return {
    projects,
    marks,
    p: withHttp((r) => handleResource(r, projectsSpec, projects)),
    t: withHttp((r) => handleResource(r, targetsSpec, targets)),
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

Deno.test("children: parent must exist (409 parent_not_found), parent filters", async () => {
  const { p, t, k, a, m } = setup();
  let res = await t(req("PUT", `targets/${T}`, targetBody()));
  assertEquals([res.status, (await res.json()).error.code], [409, "parent_not_found"]);

  await p(req("PUT", `projects/${P}`, projectBody()));
  await p(req("PUT", `projects/${P2}`, projectBody({ id: P2 })));
  res = await t(req("PUT", `targets/${T}`, targetBody()));
  assertEquals((await res.json()).applied, true);
  const T2 = T.replace(/d$/, "e");
  await t(req("POST", "targets", targetBody({ id: T2, projectId: P2 })));

  res = await t(req("GET", `targets?projectId=${P2.toUpperCase()}`));
  assertEquals((await res.json()).items.map((i: Target) => i.id), [T2]);
  assertEquals((await t(req("GET", "targets?projectId=bad"))).status, 400);

  res = await k(req("PUT", `plan-tasks/${K}`, planTaskBody({ targetId: P })));
  assertEquals((await res.json()).error.code, "parent_not_found");
  res = await k(req("PUT", `plan-tasks/${K}`, planTaskBody()));
  assertEquals(await res.json(), { item: planTaskBody(), applied: true });
  res = await k(req("GET", `plan-tasks?targetId=${T2}`));
  assertEquals((await res.json()).items, []);

  res = await a(req("POST", "consistent-actions/batch", { items: [actionBody()] }));
  assertEquals((await res.json()).results[0].item, actionBody());
  res = await a(req("PUT", `consistent-actions/${A}`, actionBody({ endTime: "09:00" })));
  assertEquals(res.status, 400);
  res = await a(req("GET", `consistent-actions?targetId=${T}`));
  assertEquals((await res.json()).items.length, 1);

  res = await m(req("PUT", `session-marks/${A}%7C2026-11-16`, markBody({ actionId: T })));
  assertEquals(res.status, 400); // path id does not match the body
  res = await m(req("POST", "session-marks", markBody({ actionId: T, date: "2026-11-17" })));
  assertEquals((await res.json()).error.code, "parent_not_found");
});

Deno.test("session-marks: composite id in the path, LWW un-mark, tombstone", async () => {
  const { p, t, a, m, marks } = setup();
  await p(req("PUT", `projects/${P}`, projectBody()));
  await t(req("PUT", `targets/${T}`, targetBody()));
  await a(req("PUT", `consistent-actions/${A}`, actionBody()));
  const id = `${A}|2026-11-16`;
  const path = `session-marks/${encodeURIComponent(id)}`;

  let res = await m(req("PUT", path, markBody()));
  assertEquals(await res.json(), { item: { id, ...markBody() }, applied: true });
  assert(marks.rows.has(id));

  res = await m(req("POST", "session-marks/batch", {
    items: [markBody({ attended: false, updatedAt: later }), markBody({ date: "2026-11-17" })],
  }));
  const { results } = await res.json();
  assertEquals(results.map((r: { id: string }) => r.id), [id, `${A}|2026-11-17`]);
  assertEquals(results[0].item.attended, false);

  res = await m(req("GET", `session-marks/${A.toUpperCase()}%7C2026-11-16`));
  assertEquals((await res.json()).attended, false);
  res = await m(req("GET", `session-marks/${A}%7C2026-11-18`));
  assertEquals(res.status, 404);
  res = await m(req("GET", `session-marks/${A}_2026-11-16`));
  assertEquals(res.status, 400);

  res = await m(req("GET", `session-marks?actionId=${A}`));
  assertEquals((await res.json()).items.length, 2);

  const at = "2026-11-20T00:00:00.000Z";
  res = await m(req("DELETE", `${path}?updatedAt=${at}`));
  const del = await res.json();
  assertEquals([del.applied, del.item.deletedAt, del.item.id], [true, at, id]);
});
