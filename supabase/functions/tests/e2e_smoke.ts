// deno-lint-ignore-file no-explicit-any
/**
 * End-to-end smoke test against a running stack (local `supabase start` +
 * `supabase functions serve`, or a deployed project). Not run by `deno test`.
 *
 *   SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_ANON_KEY=... \
 *     deno run --allow-net --allow-env tests/e2e_smoke.ts
 *
 * Creates two throwaway users (needs email confirmation off).
 */
const url = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const anon = Deno.env.get("SUPABASE_ANON_KEY");
if (!anon) throw new Error("Set SUPABASE_ANON_KEY");

let failures = 0;
function check(label: string, ok: boolean, extra?: unknown) {
  console.log(`${ok ? "ok  " : "FAIL"} ${label}`, ok ? "" : JSON.stringify(extra));
  if (!ok) failures++;
}

async function call(
  method: string,
  path: string,
  opts: { token?: string; body?: unknown } = {},
): Promise<{ status: number; body: any; headers: Headers }> {
  const headers: Record<string, string> = { apikey: anon!, "content-type": "application/json" };
  if (opts.token) headers.authorization = `Bearer ${opts.token}`;
  const res = await fetch(`${url}/functions/v1/${path}`, {
    method,
    headers,
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
  });
  const text = await res.text();
  let body: any = text;
  try {
    body = text ? JSON.parse(text) : null;
  } catch { /* keep text */ }
  return { status: res.status, body, headers: res.headers };
}

const stamp = Date.now();
const email = `smoke+${stamp}@example.com`;
const password = "Sm0ke-test-pass!";

let r = await call("OPTIONS", "habits");
check("CORS preflight", r.status === 200 && !!r.headers.get("access-control-allow-origin"), r);

r = await call("POST", "auth-register", { body: { email, password, displayName: "Smoke" } });
check("register → session", r.status === 200 && !!r.body?.session?.accessToken, r);
r = await call("POST", "auth-register", { body: { email, password } });
check(
  "register again → 409 email_taken",
  r.status === 409 && r.body?.error?.code === "email_taken",
  r,
);

r = await call("POST", "auth-login", { body: { email, password: "wrong" } });
check(
  "login wrong → 401 invalid_credentials",
  r.status === 401 && r.body?.error?.code === "invalid_credentials",
  r,
);
r = await call("POST", "auth-login", { body: { email, password } });
check("login → session", r.status === 200 && Number.isInteger(r.body?.session?.expiresAt), r);
let session = r.body.session;

r = await call("POST", "auth-refresh", { body: { refreshToken: session.refreshToken } });
check("refresh → new session", r.status === 200 && !!r.body?.session?.accessToken, r);
session = r.body.session;
r = await call("POST", "auth-refresh", { body: { refreshToken: "nope" } });
check(
  "refresh bad → 401 invalid_refresh_token",
  r.status === 401 && r.body?.error?.code === "invalid_refresh_token",
  r,
);

const t = session.accessToken;
r = await call("GET", "habits");
check("no token → 401 unauthorized", r.status === 401 && r.body?.error?.code === "unauthorized", r);
r = await call("GET", "habits", { token: "garbage" });
check(
  "bad token → 401 unauthorized",
  r.status === 401 && r.body?.error?.code === "unauthorized",
  r,
);

const habit = {
  id: "h1",
  name: "Drink water",
  emoji: "💧",
  color: 4280391411,
  schedule: { type: "daily" },
  reminderTime: "08:30",
  createdAt: "2026-10-01T08:00:00.000Z",
  archived: false,
  updatedAt: "2026-10-07T09:15:00.000Z",
  deletedAt: null,
};
r = await call("PUT", "habits/h1", { token: t, body: habit });
check(
  "PUT habit applied",
  r.status === 200 && r.body.applied === true && r.body.item.color === 4280391411,
  r,
);
check(
  "PUT habit echoes contract JSON",
  JSON.stringify(r.body.item) === JSON.stringify(habit),
  r.body,
);
r = await call("PUT", "habits/h1", {
  token: t,
  body: { ...habit, name: "older", updatedAt: "2026-10-01T00:00:00.000Z" },
});
check(
  "PUT older → applied false, stored row",
  r.body.applied === false && r.body.item.name === "Drink water",
  r,
);
r = await call("GET", "habits", { token: t });
check(
  "GET habits lists 1",
  r.status === 200 && r.body.items.length === 1 && typeof r.body.serverTime === "string",
  r,
);
const cursor = r.body.serverTime;
r = await call("GET", "habits/h1", { token: t });
check("GET habit by id", r.status === 200 && r.body.id === "h1", r);
r = await call("GET", "habits/none", { token: t });
check("GET missing → 404", r.status === 404 && r.body.error.code === "not_found", r);

const ci = {
  id: "h1_2026-10-07",
  habitId: "h1",
  date: "2026-10-07",
  completed: true,
  updatedAt: "2026-10-07T09:16:00.000Z",
  deletedAt: null,
};
r = await call("PUT", "check-ins/h1_2026-10-07", { token: t, body: ci });
check(
  "PUT check-in applied",
  r.body.applied === true && JSON.stringify(r.body.item) === JSON.stringify(ci),
  r,
);
r = await call("POST", "check-ins/batch", {
  token: t,
  body: { items: [{ ...ci, id: "zz_2026-10-07", habitId: "zz" }] },
});
check(
  "check-in for unknown habit → 409 habit_not_found",
  r.status === 409 && r.body.error.code === "habit_not_found",
  r,
);
r = await call("POST", "habits/batch", {
  token: t,
  body: { items: [habit, { ...habit, id: "h2" }] },
});
check(
  "habits batch",
  r.status === 200 && r.body.results[0].applied === false && r.body.results[1].applied === true,
  r,
);
r = await call("DELETE", "habits/h2?updatedAt=2026-10-08T00:00:00.000Z", { token: t });
check(
  "DELETE → tombstone",
  r.status === 200 && r.body.applied && r.body.item.deletedAt === "2026-10-08T00:00:00.000Z",
  r,
);
r = await call("GET", `habits?since=${encodeURIComponent(cursor)}`, { token: t });
check(
  "delta pull includes new + tombstoned h2",
  r.status === 200 && r.body.items.some((i: any) => i.id === "h2" && i.deletedAt),
  r,
);
r = await call("GET", "check-ins?habitId=h1", { token: t });
check("check-ins habitId filter", r.status === 200 && r.body.items.length === 1, r);

r = await call("GET", "game-state", { token: t });
check("game-state empty", r.status === 200 && r.body.item === null, r);
const gs = {
  state: { version: 1, checkIns: { "h1|2026-10-07": 10 } },
  updatedAt: "2026-10-07T09:16:00.000Z",
};
r = await call("PUT", "game-state", { token: t, body: gs });
check(
  "game-state PUT",
  r.body.applied === true && JSON.stringify(r.body.item) === JSON.stringify(gs),
  r,
);
r = await call("PUT", "game-state", {
  token: t,
  body: { ...gs, updatedAt: "2026-10-07T09:00:00.000Z" },
});
check("game-state older → not applied", r.body.applied === false, r);

// Projects (docs/PROJECTS.md): parent-first, LWW, filters, session marks.
const P = crypto.randomUUID();
const G = crypto.randomUUID();
const K = crypto.randomUUID();
const B = crypto.randomUUID();
const A = crypto.randomUUID();
const ts = (d: string) => `2026-11-${d}T08:00:00.000Z`;
const project = {
  id: P,
  name: "Content business",
  archived: false,
  createdAt: ts("01"),
  updatedAt: ts("01"),
  deletedAt: null,
};
const goal = {
  id: G,
  projectId: P,
  title: "5 videos",
  deadline: "2026-11-30",
  status: "inProgress",
  createdAt: ts("01"),
  updatedAt: ts("01"),
  deletedAt: null,
};
const task = {
  id: K,
  goalId: G,
  title: "5 scripts",
  deliveryDate: "2026-11-10",
  done: false,
  position: 0,
  createdAt: ts("01"),
  updatedAt: ts("01"),
  deletedAt: null,
};
const block = {
  id: B,
  projectId: P,
  label: "Deep work",
  startTime: "10:00",
  endTime: "13:00",
  recurrence: { type: "weekly", weekdays: [1, 2, 3, 4, 5] },
  startDate: "2026-11-02",
  endDate: null,
  createdAt: ts("01"),
  updatedAt: ts("01"),
  deletedAt: null,
};
const action = {
  id: A,
  goalId: G,
  text: "Write 500 words",
  sortOrder: 0,
  createdAt: ts("01"),
  updatedAt: ts("01"),
  deletedAt: null,
};
const markId = `${B}|2026-11-16`;
const mark = {
  timeBlockId: B,
  date: "2026-11-16",
  attended: true,
  updatedAt: ts("02"),
  deletedAt: null,
};

r = await call("GET", "projects");
check("projects: no token → 401", r.status === 401 && r.body?.error?.code === "unauthorized", r);
r = await call("GET", "targets", { token: t });
check("targets function is gone → 404", r.status === 404, r);
r = await call("PUT", `goals/${G}`, { token: t, body: goal });
check(
  "goal before its project → 409 parent_not_found",
  r.status === 409 && r.body?.error?.code === "parent_not_found",
  r,
);
r = await call("PUT", `time-blocks/${B}`, { token: t, body: block });
check(
  "time block before its project → 409 parent_not_found",
  r.status === 409 && r.body?.error?.code === "parent_not_found" &&
    String(r.body?.error?.message).includes("project"),
  r,
);
r = await call("PUT", `projects/${P}`, { token: t, body: project });
check(
  "PUT project echoes contract JSON",
  r.status === 200 && r.body.applied === true &&
    JSON.stringify(r.body.item) === JSON.stringify(project),
  r,
);
const pCursor = (await call("GET", "projects", { token: t })).body.serverTime;
r = await call("PUT", `projects/${P}`, {
  token: t,
  body: { ...project, name: "older", updatedAt: "2026-10-01T00:00:00.000Z" },
});
check(
  "PUT older project → applied false",
  r.body.applied === false && r.body.item.name === project.name,
  r,
);
r = await call("PUT", `consistent-actions/${A}`, { token: t, body: action });
check(
  "consistent action before its goal → 409 parent_not_found",
  r.status === 409 && String(r.body?.error?.message).includes("goal"),
  r,
);
r = await call("POST", "goals/batch", { token: t, body: { items: [goal] } });
check(
  "goals batch echoes contract JSON",
  r.status === 200 && JSON.stringify(r.body.results[0].item) === JSON.stringify(goal),
  r,
);
r = await call("PUT", `plan-tasks/${K}`, { token: t, body: task });
check("PUT plan task", r.status === 200 && JSON.stringify(r.body.item) === JSON.stringify(task), r);
r = await call("PUT", `time-blocks/${B}`, { token: t, body: block });
check(
  "PUT time block (label, recurrence jsonb, dates round-trip)",
  r.status === 200 && JSON.stringify(r.body.item) === JSON.stringify(block),
  r,
);
r = await call("PUT", `time-blocks/${B}`, {
  token: t,
  body: { ...block, label: null, endDate: "2026-12-31", updatedAt: ts("03") },
});
check(
  "time block label null + endDate",
  r.status === 200 && r.body.item.label === null && r.body.item.endDate === "2026-12-31",
  r,
);
r = await call("PUT", `time-blocks/${crypto.randomUUID()}`, {
  token: t,
  body: { ...block, id: undefined, endTime: "09:00" },
});
check(
  "block end before start → 400",
  r.status === 400 && r.body.error.code === "invalid_input",
  r,
);
r = await call("PUT", `time-blocks/${crypto.randomUUID()}`, {
  token: t,
  body: { ...block, id: undefined, endDate: "2026-11-01" },
});
check("block endDate before startDate → 400", r.status === 400, r);
r = await call("PUT", `time-blocks/${crypto.randomUUID()}`, {
  token: t,
  body: { ...block, id: undefined, startTime: "11:00", endTime: "12:00" },
});
check(
  "overlapping block is accepted (overlap is an app rule)",
  r.status === 200 && r.body.applied,
  r,
);
r = await call("PUT", `consistent-actions/${A}`, { token: t, body: action });
check(
  "PUT consistent action (text item) echoes contract JSON",
  r.status === 200 && JSON.stringify(r.body.item) === JSON.stringify(action),
  r,
);
r = await call("POST", "consistent-actions/batch", {
  token: t,
  body: { items: [{ ...action, id: crypto.randomUUID(), text: "Edit", sortOrder: 1 }] },
});
check("consistent actions batch", r.status === 200 && r.body.results[0].applied, r);
r = await call("PUT", `consistent-actions/${A}`, {
  token: t,
  body: { ...action, text: "x".repeat(501), updatedAt: ts("04") },
});
check("consistent action text > 500 → 400", r.status === 400, r);
r = await call("PUT", `session-marks/${encodeURIComponent(markId)}`, { token: t, body: mark });
check(
  "PUT session mark (derived id)",
  r.status === 200 && r.body.item.id === markId && r.body.item.attended === true &&
    r.body.item.timeBlockId === B,
  r,
);
r = await call("POST", "session-marks/batch", {
  token: t,
  body: { items: [{ ...mark, attended: false, updatedAt: ts("03") }] },
});
check(
  "un-mark via batch (LWW), results id is the key",
  r.status === 200 && r.body.results[0].id === markId && r.body.results[0].item.attended === false,
  r,
);
r = await call("PUT", `session-marks/${encodeURIComponent(`${G}|2026-11-16`)}`, {
  token: t,
  body: { ...mark, timeBlockId: G },
});
check(
  "session mark of an unknown time block → 409",
  r.status === 409 && String(r.body?.error?.message).includes("time block"),
  r,
);
r = await call("GET", `session-marks/${encodeURIComponent(markId)}`, { token: t });
check("GET session mark by key", r.status === 200 && r.body.attended === false, r);
r = await call("DELETE", `session-marks/${encodeURIComponent(markId)}?updatedAt=${ts("04")}`, {
  token: t,
});
check("DELETE session mark → tombstone", r.status === 200 && r.body.item.deletedAt === ts("04"), r);
r = await call("GET", `session-marks?timeBlockId=${B}`, { token: t });
check("session-marks timeBlockId filter", r.status === 200 && r.body.items.length === 1, r);
r = await call("GET", `goals?projectId=${P}`, { token: t });
check("goals projectId filter", r.status === 200 && r.body.items.length === 1, r);
r = await call("GET", `time-blocks?projectId=${P}`, { token: t });
check("time-blocks projectId filter", r.status === 200 && r.body.items.length === 2, r);
r = await call("GET", `plan-tasks?goalId=${G}`, { token: t });
check("plan-tasks goalId filter", r.status === 200 && r.body.items.length === 1, r);
r = await call("GET", `consistent-actions?goalId=${G}`, { token: t });
check("consistent-actions goalId filter", r.status === 200 && r.body.items.length === 2, r);
r = await call("DELETE", `consistent-actions/${A}?updatedAt=${ts("05")}`, { token: t });
check("DELETE consistent action → tombstone", r.status === 200 && r.body.applied, r);
r = await call("DELETE", `time-blocks/${B}?updatedAt=${ts("05")}`, { token: t });
check("DELETE time block → tombstone", r.status === 200 && r.body.applied, r);
r = await call("DELETE", `goals/${G}?updatedAt=${ts("05")}`, { token: t });
check("DELETE goal → tombstone", r.status === 200 && r.body.item.deletedAt === ts("05"), r);
r = await call("DELETE", `projects/${P}?updatedAt=${ts("05")}`, { token: t });
check("DELETE project → tombstone", r.status === 200 && r.body.item.deletedAt === ts("05"), r);
r = await call("GET", `projects?since=${encodeURIComponent(pCursor)}`, { token: t });
check(
  "projects delta pull includes the tombstone",
  r.status === 200 && r.body.items.some((i: any) => i.id === P && i.deletedAt),
  r,
);
r = await call("GET", `projects/${crypto.randomUUID()}`, { token: t });
check("GET missing project → 404", r.status === 404, r);

// Isolation: a second user sees nothing of the first.
r = await call("POST", "auth-register", {
  body: { email: `smoke2+${stamp}@example.com`, password },
});
const t2 = r.body.session.accessToken;
r = await call("GET", "habits", { token: t2 });
check("RLS: other user sees no habits", r.status === 200 && r.body.items.length === 0, r);
r = await call("GET", "habits/h1", { token: t2 });
check("RLS: other user cannot read h1", r.status === 404, r);
r = await call("PUT", "habits/h1", { token: t2, body: habit });
check("RLS: same id for other user is a separate row", r.body.applied === true, r);
r = await call("GET", "game-state", { token: t2 });
check("RLS: other user has no game state", r.body.item === null, r);
for (
  const f of [
    "projects",
    "goals",
    "time-blocks",
    "plan-tasks",
    "consistent-actions",
    "session-marks",
  ]
) {
  r = await call("GET", f, { token: t2 });
  check(`RLS: other user sees no ${f}`, r.status === 200 && r.body.items.length === 0, r);
}
r = await call("PUT", `goals/${crypto.randomUUID()}`, {
  token: t2,
  body: { ...goal, id: undefined },
});
check("RLS: other user cannot attach a goal to user 1's project", r.status === 409, r);
r = await call("PUT", `time-blocks/${crypto.randomUUID()}`, {
  token: t2,
  body: { ...block, id: undefined },
});
check("RLS: other user cannot attach a time block to user 1's project", r.status === 409, r);

// account-delete removes the Projects rows too (explicit deletes + FK cascade).
r = await call("POST", "auth-register", {
  body: { email: `smoke3+${stamp}@example.com`, password },
});
const t3 = r.body.session.accessToken;
await call("PUT", `projects/${P}`, { token: t3, body: project });
await call("PUT", `goals/${G}`, { token: t3, body: goal });
await call("PUT", `plan-tasks/${K}`, { token: t3, body: task });
await call("PUT", `consistent-actions/${A}`, { token: t3, body: action });
await call("PUT", `time-blocks/${B}`, { token: t3, body: block });
r = await call("PUT", `session-marks/${encodeURIComponent(markId)}`, { token: t3, body: mark });
check("user 3 has a full project tree", r.status === 200 && r.body.applied, r);
r = await call("POST", "account-delete", { token: t3, body: { confirm: "DELETE" } });
check("account-delete with Projects rows → 204", r.status === 204, r);

r = await call("DELETE", "game-state", { token: t });
check("game-state reset → 204", r.status === 204, r);
r = await call("POST", "auth-logout", { token: t });
check("logout → 204", r.status === 204, r);
r = await call("POST", "auth-refresh", { body: { refreshToken: session.refreshToken } });
check("refresh after logout → 401", r.status === 401, r);

console.log(failures === 0 ? "\nALL OK" : `\n${failures} FAILED`);
if (failures) Deno.exit(1);
