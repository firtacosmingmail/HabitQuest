import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import { type AdminCaller, isAdmin, parseAdmins, requireAdmin } from "../_shared/admin.ts";
import { handleAdminQuotes, parseQuoteSearch } from "../_shared/admin_quotes.ts";
import {
  buildStats,
  fillDays,
  handleAdminStats,
  type RawStats,
  statsRange,
  STREAK_BUCKETS,
  toBuckets,
  weekStart,
  XP_BUCKETS,
} from "../_shared/admin_stats.ts";
import { ApiError, unauthorized } from "../_shared/errors.ts";
import { withHttp } from "../_shared/http.ts";
import { handleQuotes } from "../_shared/quotes.ts";
import { MemoryQuotes, req } from "./fakes.ts";

const callers: Record<string, AdminCaller> = {
  alice: { userId: "user-alice", email: "alice@example.com", serviceRole: false },
  owner: { userId: "user-owner", email: "FirtaCosmin@Gmail.com", serviceRole: false },
  service: { userId: null, email: null, serviceRole: true },
};
const ADMINS = "firtacosmin@gmail.com";
const as = (who: string) => ({ authorization: `Bearer ${who}` });

function fakeAuth(r: Request): Promise<AdminCaller> {
  const m = /^Bearer (\w+)$/.exec(r.headers.get("authorization") ?? "");
  const c = m ? callers[m[1]] : undefined;
  return c ? Promise.resolve(c) : Promise.reject(unauthorized());
}

const NOW = new Date("2026-10-20T10:00:00Z");

// Admin check -----------------------------------------------------------------

Deno.test("isAdmin: service role, or a QUOTE_ADMINS email in any case", () => {
  const admins = parseAdmins(` ${ADMINS.toUpperCase()} ; x@y.z`);
  assert(isAdmin(callers.service, []));
  assert(isAdmin(callers.owner, admins));
  assert(isAdmin({ ...callers.owner, email: " firtacosmin@gmail.com " }, admins));
  assert(!isAdmin(callers.alice, admins));
  assert(!isAdmin(callers.owner, []));
  assert(!isAdmin({ userId: "u", email: "", serviceRole: false }, admins));
  // A raw (un-parsed) list is compared case-insensitively too.
  assert(isAdmin(callers.owner, ["FIRTACOSMIN@gmail.com"]));
});

Deno.test("requireAdmin throws 403 forbidden for non-admins", () => {
  const err = assertThrows(() => requireAdmin(callers.alice, [ADMINS]), ApiError);
  assertEquals([err.status, err.code], [403, "forbidden"]);
  requireAdmin(callers.owner, [ADMINS]);
  requireAdmin(callers.service, []);
});

// admin-quotes ------------------------------------------------------------------

function quotesSetup() {
  const db = new MemoryQuotes();
  const adminQuotes = withHttp((r) =>
    handleAdminQuotes(r, {
      authenticate: fakeAuth,
      store: () => db.adminStore(),
      admins: () => parseAdmins(ADMINS),
    })
  );
  const quotes = withHttp((r) =>
    handleQuotes(r, {
      authenticate: fakeAuth,
      store: (c) => db.store(c.userId),
      admins: () => parseAdmins(ADMINS),
      now: () => NOW,
    })
  );
  const past = db.add("Well done is better than well said.", "2026-10-18", "Benjamin Franklin");
  const today = db.add("Small steps every day.", "2026-10-20");
  const future = db.add("The best is yet to come.", "2026-11-05", "Robert Browning");
  const loose = db.add("Keep going.", null);
  // Two users love the future quote, one loves the past one.
  db.loveStore("u1").love(future.id);
  db.loveStore("u2").love(future.id);
  db.loveStore("u2").love(past.id);
  return { db, adminQuotes, quotes, past, today, future, loose };
}

Deno.test("admin-quotes: 401 without a token, 403 for non-admins", async () => {
  const { adminQuotes } = quotesSetup();
  assertEquals((await adminQuotes(req("GET", "admin-quotes"))).status, 401);
  const res = await adminQuotes(req("GET", "admin-quotes", undefined, as("alice")));
  assertEquals(res.status, 403);
  assertEquals((await res.json()).error.code, "forbidden");
  const del = await adminQuotes(
    req("DELETE", "admin-quotes?id=00000000-0000-4000-8000-000000000001", undefined, as("alice")),
  );
  assertEquals(del.status, 403);
});

Deno.test("admin-quotes: lists past, today, future and unscheduled with love counts", async () => {
  const { adminQuotes, past, today, future, loose } = quotesSetup();
  for (const who of ["owner", "service"]) {
    const res = await adminQuotes(req("GET", "admin-quotes", undefined, as(who)));
    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(body.total, 4);
    assertEquals([body.limit, body.offset], [100, 0]);
    assertEquals(body.items.map((q: { id: string }) => q.id), [
      loose.id,
      future.id,
      today.id,
      past.id,
    ]);
    assertEquals(body.items.map((q: { loves: number }) => q.loves), [0, 2, 0, 1]);
    assertEquals(body.items[1].author, "Robert Browning");
    assertEquals(body.items[1].day, "2026-11-05");
  }
});

Deno.test("admin-quotes: search, date range, scheduled filter and paging", async () => {
  const { adminQuotes, past, today, future, loose } = quotesSetup();
  const ids = async (query: string) => {
    const res = await adminQuotes(req("GET", `admin-quotes?${query}`, undefined, as("owner")));
    assertEquals(res.status, 200, query);
    return (await res.json()).items.map((q: { id: string }) => q.id);
  };
  assertEquals(await ids("q=FRANKLIN"), [past.id]); // author, case-insensitive
  assertEquals(await ids("q=%20best%20"), [future.id]); // text, trimmed
  assertEquals(await ids("from=2026-10-19&to=2026-10-31"), [today.id]);
  assertEquals(await ids("from=2026-10-20"), [future.id, today.id]); // future included
  assertEquals(await ids("to=2026-10-19"), [past.id]);
  assertEquals(await ids("scheduled=unscheduled"), [loose.id]);
  assertEquals(await ids("scheduled=scheduled"), [future.id, today.id, past.id]);
  assertEquals(await ids("limit=2&offset=1"), [future.id, today.id]);
  const res = await adminQuotes(req("GET", "admin-quotes?limit=1", undefined, as("owner")));
  assertEquals((await res.json()).total, 4);
});

Deno.test("admin-quotes: invalid queries are 400", async () => {
  const { adminQuotes } = quotesSetup();
  for (
    const q of [
      "from=2026-13-01",
      "from=2026-10-21&to=2026-10-20",
      "scheduled=maybe",
      "scheduled=unscheduled&from=2026-10-01",
      "limit=0",
      "limit=501",
      "offset=-1",
      `q=${"x".repeat(201)}`,
    ]
  ) {
    const res = await adminQuotes(req("GET", `admin-quotes?${q}`, undefined, as("owner")));
    assertEquals(res.status, 400, q);
    assertEquals((await res.json()).error.code, "invalid_input");
  }
  assertEquals(parseQuoteSearch(new URLSearchParams("q=")).query, null);
});

Deno.test("admin-quotes: DELETE removes the quote and its loves", async () => {
  const { db, adminQuotes, future } = quotesSetup();
  const res = await adminQuotes(
    req("DELETE", `admin-quotes?id=${future.id.toUpperCase()}`, undefined, as("owner")),
  );
  assertEquals(res.status, 204);
  assert(!db.quotes.has(future.id));
  assert(![...db.loves.values()].some((m) => m.has(future.id)));
  const again = await adminQuotes(
    req("DELETE", `admin-quotes?id=${future.id}`, undefined, as("owner")),
  );
  assertEquals(again.status, 404);
  const bad = await adminQuotes(req("DELETE", "admin-quotes?id=nope", undefined, as("owner")));
  assertEquals(bad.status, 400);
});

Deno.test("admin-quotes: other methods and sub-paths", async () => {
  const { adminQuotes } = quotesSetup();
  assertEquals((await adminQuotes(req("POST", "admin-quotes", {}, as("owner")))).status, 405);
  assertEquals(
    (await adminQuotes(req("GET", "admin-quotes/x", undefined, as("owner")))).status,
    404,
  );
  assertEquals((await adminQuotes(req("OPTIONS", "admin-quotes"))).status, 200);
});

Deno.test("unschedule through PUT /quotes {day:null} then it lists as unscheduled", async () => {
  const { adminQuotes, quotes, future } = quotesSetup();
  const put = await quotes(req("PUT", `quotes?id=${future.id}`, { day: null }, as("owner")));
  assertEquals(put.status, 200);
  assertEquals((await put.json()).quote.day, null);
  const res = await adminQuotes(
    req("GET", "admin-quotes?scheduled=unscheduled", undefined, as("owner")),
  );
  const items = (await res.json()).items;
  assert(items.some((q: { id: string; loves: number }) => q.id === future.id && q.loves === 2));
  // The shared admin check also guards the public quotes writes.
  const denied = await quotes(req("PUT", `quotes?id=${future.id}`, { day: null }, as("alice")));
  assertEquals(denied.status, 403);
});

// admin-stats: aggregation helpers -----------------------------------------------

Deno.test("fillDays fills the range with zeros and ignores days outside it", () => {
  assertEquals(
    fillDays(
      [{ d: "2026-10-01", n: 9 }, { d: "2026-10-03", n: 2 }, { d: "2026-10-05", n: 4 }],
      "2026-10-02",
      "2026-10-05",
    ),
    [0, 2, 0, 4],
  );
  assertEquals(fillDays([], "2026-10-02", "2026-10-02"), [0]);
});

Deno.test("weekStart is the ISO Monday", () => {
  assertEquals(weekStart("2026-10-19"), "2026-10-19"); // Monday
  assertEquals(weekStart("2026-10-25"), "2026-10-19"); // Sunday
  assertEquals(weekStart("2026-10-18"), "2026-10-12");
  assertEquals(weekStart("1970-01-01"), "1969-12-29");
});

Deno.test("toBuckets groups values into the fixed buckets", () => {
  const xp = toBuckets(
    [{ v: 0, n: 3 }, { v: 10, n: 2 }, { v: 99, n: 1 }, { v: 100, n: 4 }, { v: 20000, n: 1 }],
    XP_BUCKETS,
  );
  assertEquals(xp.map((b) => b.label), [
    "0",
    "1–99",
    "100–499",
    "500–999",
    "1000–2499",
    "2500–4999",
    "5000–9999",
    "10000+",
  ]);
  assertEquals(xp.map((b) => b.users), [3, 3, 4, 0, 0, 0, 0, 1]);
  const streaks = toBuckets([{ v: 7, n: 2 }, { v: 13, n: 1 }, { v: 365, n: 1 }], STREAK_BUCKETS);
  assertEquals(streaks.map((b) => b.users), [0, 0, 0, 3, 0, 0, 0, 1]);
  // A negative value (malformed state) is counted in the first bucket.
  assertEquals(toBuckets([{ v: -5, n: 1 }], XP_BUCKETS)[0].users, 1);
});

Deno.test("statsRange: default last 30 days, validation and the 366-day cap", () => {
  assertEquals(statsRange(new URLSearchParams(), "2026-10-20"), {
    from: "2026-09-21",
    to: "2026-10-20",
  });
  assertEquals(statsRange(new URLSearchParams("to=2026-10-10"), "2026-10-20").from, "2026-09-11");
  assertEquals(
    statsRange(new URLSearchParams("from=2026-01-01&to=2027-01-01"), "2026-10-20").to,
    "2027-01-01",
  );
  for (const q of ["from=2026-10-21&to=2026-10-20", "from=2025-01-01&to=2026-10-20", "to=x"]) {
    assertThrows(() => statsRange(new URLSearchParams(q), "2026-10-20"), ApiError, undefined, q);
  }
});

const RAW: RawStats = {
  totals: {
    users: 12,
    players: 9,
    habits: 30,
    active_habits: 25,
    completions: 400,
    quotes: 90,
    scheduled_quotes: 88,
    quote_loves: 15,
  },
  in_range: { signups: 3, active_users: 5, habits_created: 7, completions: 21, quote_loves: 4 },
  signups: [{ d: "2026-10-14", n: 1 }, { d: "2026-10-19", n: 2 }],
  active: [{ d: "2026-10-14", n: 3 }, { d: "2026-10-19", n: 4 }, { d: "2026-10-20", n: 3 }],
  weekly_active: [{ w: "2026-10-12", n: 3 }, { w: "2026-10-19", n: 5 }],
  habits_created: [{ d: "2026-10-15", n: 7 }],
  completions: [{ d: "2026-10-14", n: 6 }, { d: "2026-10-19", n: 9 }, { d: "2026-10-20", n: 6 }],
  loves: [{ d: "2026-10-20", n: 4 }],
  xp: [{ v: 0, n: 2 }, { v: 150, n: 5 }, { v: 1200, n: 2 }],
  best_streak: [{ v: 0, n: 2 }, { v: 4, n: 6 }, { v: 30, n: 1 }],
  level: [{ v: 1, n: 2 }, { v: 2, n: 5 }, { v: 5, n: 2 }],
  top_quotes: [{ id: "q1", text: "Keep going.", author: null, day: "2026-10-20", loves: 4 }],
};

Deno.test("buildStats: daily series, weekly sums, buckets and totals", () => {
  const s = buildStats(RAW, "2026-10-14", "2026-10-20", NOW);
  assertEquals(s.days, 7);
  assertEquals(s.daily.map((d) => d.date), [
    "2026-10-14",
    "2026-10-15",
    "2026-10-16",
    "2026-10-17",
    "2026-10-18",
    "2026-10-19",
    "2026-10-20",
  ]);
  assertEquals(s.daily.map((d) => d.completions), [6, 0, 0, 0, 0, 9, 6]);
  assertEquals(s.daily.map((d) => d.activeUsers), [3, 0, 0, 0, 0, 4, 3]);
  assertEquals(s.daily[1].habitsCreated, 7);
  assertEquals(s.daily[6].quoteLoves, 4);
  // 2026-10-14..18 is the end of the week of Monday 12th; 19..20 starts the next.
  assertEquals(s.weekly, [
    { weekStart: "2026-10-12", days: 5, signups: 1, completions: 6, activeUsers: 3 },
    { weekStart: "2026-10-19", days: 2, signups: 2, completions: 15, activeUsers: 5 },
  ]);
  assertEquals(s.range.averageDailyActiveUsers, 1.4); // (3 + 4 + 3) / 7
  assertEquals(s.totals.users, 12);
  assertEquals(s.totals.usersWithGameState, 9);
  assertEquals(s.xpBuckets.map((b) => b.users), [2, 0, 5, 0, 2, 0, 0, 0]);
  assertEquals(s.bestStreakBuckets.map((b) => b.users), [2, 0, 6, 0, 0, 1, 0, 0]);
  assertEquals(s.levels, [{ level: 1, users: 2 }, { level: 2, users: 5 }, { level: 5, users: 2 }]);
  assertEquals(s.topQuotes[0].loves, 4);
  assertEquals(s.widgets.recorded, false);
  assertEquals(s.generatedAt, NOW.toISOString());
});

Deno.test("buildStats: an empty database gives zeros, not errors", () => {
  const empty = {
    totals: {},
    in_range: {},
    signups: [],
    active: [],
    weekly_active: [],
    habits_created: [],
    completions: [],
    loves: [],
    xp: [],
    best_streak: [],
    level: [],
    top_quotes: [],
  } as unknown as RawStats;
  const s = buildStats(empty, "2026-10-20", "2026-10-20", NOW);
  assertEquals(s.totals.users, 0);
  assertEquals(s.daily, [{
    date: "2026-10-20",
    signups: 0,
    activeUsers: 0,
    habitsCreated: 0,
    completions: 0,
    quoteLoves: 0,
  }]);
  assert(s.xpBuckets.every((b) => b.users === 0));
});

// admin-stats: handler -----------------------------------------------------------

function statsSetup() {
  const calls: { from: string; to: string }[] = [];
  const stats = withHttp((r) =>
    handleAdminStats(r, {
      authenticate: fakeAuth,
      store: () => ({
        raw: (from, to) => {
          calls.push({ from, to });
          return Promise.resolve(RAW);
        },
      }),
      admins: () => parseAdmins(ADMINS),
      now: () => NOW,
    })
  );
  return { stats, calls };
}

Deno.test("admin-stats: non-admins get 403 and never reach the store", async () => {
  const { stats, calls } = statsSetup();
  assertEquals((await stats(req("GET", "admin-stats"))).status, 401);
  assertEquals((await stats(req("GET", "admin-stats", undefined, as("alice")))).status, 403);
  assertEquals((await stats(req("GET", "admin-stats/me", undefined, as("alice")))).status, 403);
  assertEquals(calls.length, 0);
});

Deno.test("admin-stats/me: the sign-in gate", async () => {
  const { stats, calls } = statsSetup();
  const res = await stats(req("GET", "admin-stats/me", undefined, as("owner")));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), {
    admin: true,
    email: "FirtaCosmin@Gmail.com",
    serviceRole: false,
  });
  assertEquals(calls.length, 0);
});

Deno.test("admin-stats: aggregates for the range, defaults to the last 30 days", async () => {
  const { stats, calls } = statsSetup();
  let res = await stats(req("GET", "admin-stats", undefined, as("owner")));
  assertEquals(res.status, 200);
  assertEquals(calls.at(-1), { from: "2026-09-21", to: "2026-10-20" });
  assertEquals((await res.json()).daily.length, 30);

  res = await stats(
    req("GET", "admin-stats?from=2026-10-14&to=2026-10-20", undefined, as("service")),
  );
  const body = await res.json();
  assertEquals(calls.at(-1), { from: "2026-10-14", to: "2026-10-20" });
  assertEquals(body.range.completions, 21);
  assertEquals(body.daily.length, 7);
  // Aggregates only: no per-user data anywhere in the response.
  const text = JSON.stringify(body);
  for (const forbiddenKey of ["userId", "user_id", "email", 'name"']) {
    assert(!text.includes(forbiddenKey), forbiddenKey);
  }
});

Deno.test("admin-stats: bad ranges, methods and paths", async () => {
  const { stats } = statsSetup();
  const bad = await stats(
    req("GET", "admin-stats?from=2026-10-21&to=2026-10-20", undefined, as("owner")),
  );
  assertEquals(bad.status, 400);
  assertEquals((await stats(req("POST", "admin-stats", {}, as("owner")))).status, 405);
  assertEquals((await stats(req("GET", "admin-stats/x", undefined, as("owner")))).status, 404);
});
