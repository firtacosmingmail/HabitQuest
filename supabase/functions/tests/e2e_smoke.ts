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

r = await call("DELETE", "game-state", { token: t });
check("game-state reset → 204", r.status === 204, r);
r = await call("POST", "auth-logout", { token: t });
check("logout → 204", r.status === 204, r);
r = await call("POST", "auth-refresh", { body: { refreshToken: session.refreshToken } });
check("refresh after logout → 401", r.status === 401, r);

console.log(failures === 0 ? "\nALL OK" : `\n${failures} FAILED`);
if (failures) Deno.exit(1);
