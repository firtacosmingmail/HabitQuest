import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import { ApiError, unauthorized } from "../_shared/errors.ts";
import { withHttp } from "../_shared/http.ts";
import {
  epochDay,
  fallbackIndex,
  fromEpochDay,
  handleQuoteLoves,
  handleQuotes,
  historyRange,
  isAdmin,
  parseAdmins,
  type QuoteCaller,
  quoteForDate,
} from "../_shared/quotes.ts";
import { validateQuoteInput, validateQuotePatch } from "../_shared/validation.ts";
import { MemoryQuotes, req } from "./fakes.ts";

const callers: Record<string, QuoteCaller> = {
  alice: { userId: "user-alice", email: "alice@example.com", serviceRole: false },
  bob: { userId: "user-bob", email: "bob@example.com", serviceRole: false },
  admin: { userId: "user-admin", email: "Admin@Example.com", serviceRole: false },
  service: { userId: null, email: null, serviceRole: true },
};

const as = (who: string) => ({ authorization: `Bearer ${who}` });

function fakeAuth(r: Request): Promise<QuoteCaller> {
  const m = /^Bearer (\w+)$/.exec(r.headers.get("authorization") ?? "");
  const c = m ? callers[m[1]] : undefined;
  return c ? Promise.resolve(c) : Promise.reject(unauthorized());
}

const NOW = new Date("2026-10-20T10:00:00Z"); // UTC today = 2026-10-20

function setup() {
  const db = new MemoryQuotes();
  const quotes = withHttp((r) =>
    handleQuotes(r, {
      authenticate: fakeAuth,
      store: (c) => db.store(c.userId),
      admins: () => parseAdmins("admin@example.com, other@example.com"),
      now: () => NOW,
    })
  );
  const loves = withHttp((r) =>
    handleQuoteLoves(r, {
      authenticate: fakeAuth,
      store: (c) => db.loveStore(c.userId!),
    })
  );
  return { db, quotes, loves };
}

/** Seeds one quote per day for [n] days from [start]. */
function seedDays(db: MemoryQuotes, start: string, n: number) {
  const s = epochDay(start);
  return Array.from({ length: n }, (_, i) => db.add(`Quote ${i}`, fromEpochDay(s + i)));
}

async function body(res: Response) {
  return await res.json();
}

// Dates and fallback ------------------------------------------------------------

Deno.test("epochDay / fromEpochDay round-trip", () => {
  assertEquals(epochDay("1970-01-01"), 0);
  assertEquals(epochDay("1970-01-02"), 1);
  assertEquals(epochDay("1969-12-31"), -1);
  assertEquals(epochDay("2027-01-14"), 20832);
  assertEquals(fromEpochDay(20832), "2027-01-14");
});

Deno.test("fallbackIndex is in range, also before 1970", () => {
  assertEquals(fallbackIndex("1970-01-01", 7), 0);
  assertEquals(fallbackIndex("1970-01-08", 7), 0);
  assertEquals(fallbackIndex("1970-01-09", 7), 1);
  assertEquals(fallbackIndex("1969-12-31", 7), 6);
  assertEquals(fallbackIndex("2027-01-14", 90), 20832 % 90);
});

Deno.test("scheduled day: returns that quote, fallback false", async () => {
  const { db } = setup();
  const qs = seedDays(db, "2026-10-16", 90);
  const d = await quoteForDate(db.store(null), "2026-10-20");
  assertEquals(d, { date: "2026-10-20", fallback: false, quote: qs[4] });
});

Deno.test("fallback is deterministic and picks (day,id) index epochDay mod count", async () => {
  const { db } = setup();
  const qs = seedDays(db, "2026-10-16", 90);
  const date = "2027-01-14"; // first day after the seed
  const a = await quoteForDate(db.store(null), date);
  const b = await quoteForDate(db.store("user-alice"), date);
  assertEquals(a, b);
  assertEquals(a!.fallback, true);
  assertEquals(a!.quote, qs[epochDay(date) % 90]);
});

Deno.test("fallback only uses quotes older than the date", async () => {
  const { db } = setup();
  const old = db.add("old", "2026-10-01");
  db.add("future", "2026-12-01");
  db.add("unscheduled", null);
  // Only one older quote: every gap day before 2026-12-01 gets it.
  for (const date of ["2026-10-02", "2026-10-03", "2026-11-30"]) {
    const d = await quoteForDate(db.store(null), date);
    assertEquals(d!.quote.id, old.id);
    assertEquals(d!.fallback, true);
  }
});

Deno.test("fallback wraps around consecutive days", async () => {
  const { db } = setup();
  const qs = seedDays(db, "2026-10-16", 3);
  const start = epochDay("2026-10-19");
  const picks: string[] = [];
  for (let i = 0; i < 6; i++) {
    const d = await quoteForDate(db.store(null), fromEpochDay(start + i));
    assertEquals(d!.fallback, true);
    picks.push(d!.quote.id);
  }
  // index = epochDay mod 3 cycles through all three quotes, then repeats.
  assertEquals(picks.slice(0, 3), picks.slice(3));
  assertEquals(new Set(picks).size, 3);
  assertEquals(picks[0], qs[start % 3].id);
});

Deno.test("fallback ties on day are ordered by id; null days last", async () => {
  const { db } = setup();
  const a = db.add("a", null);
  const b = db.add("b", null);
  const c = db.add("c", "2030-01-01");
  // No quote is older than 2026-01-01 → all quotes, ordered c, a, b.
  const date = "2026-01-01";
  const d = await quoteForDate(db.store(null), date);
  assertEquals(d!.quote.id, [c, a, b][epochDay(date) % 3].id);
});

Deno.test("no quotes at all → 404 not_found", async () => {
  const { quotes } = setup();
  const res = await quotes(req("GET", "quotes", undefined, as("alice")));
  assertEquals(res.status, 404);
  assertEquals((await body(res)).error.code, "not_found");
});

// GET /quotes ------------------------------------------------------------------

Deno.test("GET defaults to today (UTC) and includes loved", async () => {
  const { db, quotes, loves } = setup();
  const qs = seedDays(db, "2026-10-16", 10);
  let res = await quotes(req("GET", "quotes", undefined, as("alice")));
  assertEquals(res.status, 200);
  let b = await body(res);
  assertEquals(b.date, "2026-10-20");
  assertEquals(b.fallback, false);
  assertEquals(b.quote, { ...qs[4], loved: false });

  await loves(req("POST", "quote-loves", { quoteId: qs[4].id }, as("alice")));
  b = await body(await quotes(req("GET", "quotes?date=2026-10-20", undefined, as("alice"))));
  assertEquals(b.quote.loved, true);
  // Bob does not love it.
  b = await body(await quotes(req("GET", "quotes?date=2026-10-20", undefined, as("bob"))));
  assertEquals(b.quote.loved, false);
  // Any date may be asked for, including a future one (fallback).
  res = await quotes(req("GET", "quotes?date=2027-03-01", undefined, as("bob")));
  assertEquals((await body(res)).fallback, true);
});

Deno.test("GET requires a token and a valid date", async () => {
  const { db, quotes } = setup();
  seedDays(db, "2026-10-16", 3);
  assertEquals((await quotes(req("GET", "quotes"))).status, 401);
  for (const q of ["2026-13-01", "2026-02-30", "20261020", "x"]) {
    const res = await quotes(req("GET", `quotes?date=${q}`, undefined, as("alice")));
    assertEquals(res.status, 400, q);
    assertEquals((await body(res)).error.code, "invalid_input");
  }
});

Deno.test("history: from/to never returns future days, newest first", async () => {
  const { db, quotes } = setup();
  const qs = seedDays(db, "2026-10-16", 30);
  const res = await quotes(
    req("GET", "quotes?from=2026-10-17&to=2026-11-30", undefined, as("alice")),
  );
  assertEquals(res.status, 200);
  const b = await body(res);
  assertEquals(b.from, "2026-10-17");
  assertEquals(b.to, "2026-10-20"); // capped at today
  assertEquals(
    b.items.map((q: { id: string }) => q.id),
    [qs[4], qs[3], qs[2], qs[1]].map((q) => q.id),
  );
  assert(b.items.every((q: { loved: boolean }) => q.loved === false));
});

Deno.test("history: past=N is the N days before today", async () => {
  const { db, quotes } = setup();
  const qs = seedDays(db, "2026-10-16", 30);
  const b = await body(await quotes(req("GET", "quotes?past=3", undefined, as("alice"))));
  assertEquals(b.from, "2026-10-17");
  assertEquals(b.to, "2026-10-19");
  assertEquals(b.items.map((q: { day: string }) => q.day), [qs[3], qs[2], qs[1]].map((q) => q.day));
});

Deno.test("history: an entirely future range is empty", async () => {
  const { db, quotes } = setup();
  seedDays(db, "2026-10-16", 30);
  const b = await body(
    await quotes(req("GET", "quotes?from=2026-11-01&to=2026-11-05", undefined, as("alice"))),
  );
  assertEquals(b.items, []);
});

Deno.test("history: parameter validation", () => {
  const today = "2026-10-20";
  const bad = [
    "past=0",
    "past=367",
    "past=-1",
    "past=1.5",
    "past=3&from=2026-10-01",
    "from=2026-10-01",
    "to=2026-10-01",
    "from=2026-10-05&to=2026-10-01",
    "from=2025-01-01&to=2026-10-01",
    "from=bad&to=2026-10-01",
  ];
  for (const q of bad) {
    assertThrows(() => historyRange(new URLSearchParams(q), today), ApiError, undefined, q);
  }
  assertEquals(historyRange(new URLSearchParams("past=366"), today).from, "2025-10-19");
});

Deno.test("GET with date and a history range is rejected", async () => {
  const { quotes } = setup();
  const res = await quotes(req("GET", "quotes?date=2026-10-20&past=3", undefined, as("alice")));
  assertEquals(res.status, 400);
});

// Admin writes -------------------------------------------------------------------

Deno.test("admin check: service role or a QUOTE_ADMINS email, case-insensitive", () => {
  const admins = parseAdmins(" Admin@Example.com ,x@y.z;\nother@example.com ");
  assertEquals(admins, ["admin@example.com", "x@y.z", "other@example.com"]);
  assert(isAdmin(callers.service, []));
  assert(isAdmin(callers.admin, admins));
  assert(!isAdmin(callers.alice, admins));
  assert(!isAdmin(callers.admin, []));
  assert(!isAdmin({ userId: "u", email: null, serviceRole: false }, admins));
  assertEquals(parseAdmins(undefined), []);
});

Deno.test("POST: non-admins get 403, admins create (201)", async () => {
  const { db, quotes } = setup();
  const input = { text: "  Keep going.  ", author: " Someone ", day: "2026-12-01" };
  let res = await quotes(req("POST", "quotes", input, as("alice")));
  assertEquals(res.status, 403);
  assertEquals((await body(res)).error.code, "forbidden");
  assertEquals(db.quotes.size, 0);
  assertEquals((await quotes(req("POST", "quotes", input))).status, 401);

  for (const who of ["admin", "service"]) {
    const day = who === "admin" ? "2026-12-01" : null;
    res = await quotes(req("POST", "quotes", { ...input, day }, as(who)));
    assertEquals(res.status, 201, who);
    const { quote } = await body(res);
    assertEquals(quote.text, "Keep going.");
    assertEquals(quote.author, "Someone");
    assertEquals(quote.day, day);
    assertEquals(quote.loved, false);
  }
  assertEquals(db.quotes.size, 2);
});

Deno.test("POST: validation errors and day conflict", async () => {
  const { db, quotes } = setup();
  db.add("taken", "2026-12-01");
  for (const b of [{}, { text: "" }, { text: 5 }, { text: "x", day: "2026-02-30" }, []]) {
    const res = await quotes(req("POST", "quotes", b, as("admin")));
    assertEquals(res.status, 400, JSON.stringify(b));
  }
  const res = await quotes(req("POST", "quotes", { text: "x", day: "2026-12-01" }, as("admin")));
  assertEquals(res.status, 409);
  assertEquals((await body(res)).error.code, "day_taken");
});

Deno.test("PUT ?id=: admin-only partial update", async () => {
  const { db, quotes } = setup();
  const q = db.add("old text", "2026-10-20", "A");
  const other = db.add("other", "2026-10-21");
  let res = await quotes(req("PUT", `quotes?id=${q.id}`, { text: "new" }, as("bob")));
  assertEquals(res.status, 403);

  res = await quotes(req("PUT", `quotes?id=${q.id}`, { text: "new", author: null }, as("admin")));
  assertEquals(res.status, 200);
  const { quote } = await body(res);
  assertEquals([quote.text, quote.author, quote.day], ["new", null, "2026-10-20"]);

  res = await quotes(req("PUT", `quotes?id=${q.id}`, { day: other.day }, as("admin")));
  assertEquals(res.status, 409);
  res = await quotes(req("PUT", "quotes?id=not-a-uuid", { text: "x" }, as("admin")));
  assertEquals(res.status, 400);
  res = await quotes(req("PUT", `quotes?id=${q.id}`, {}, as("admin")));
  assertEquals(res.status, 400);
  res = await quotes(
    req("PUT", "quotes?id=00000000-0000-4000-8000-0000000000ff", { text: "x" }, as("service")),
  );
  assertEquals(res.status, 404);
});

Deno.test("quotes: unsupported method and sub-path", async () => {
  const { quotes } = setup();
  assertEquals((await quotes(req("DELETE", "quotes", undefined, as("admin")))).status, 405);
  assertEquals((await quotes(req("GET", "quotes/x", undefined, as("admin")))).status, 404);
  assertEquals((await quotes(req("OPTIONS", "quotes"))).status, 200);
});

Deno.test("validateQuoteInput / validateQuotePatch", () => {
  assertEquals(validateQuoteInput({ text: " a " }), { text: "a", author: null, day: null });
  assertEquals(validateQuoteInput({ text: "a", author: "  " }).author, null);
  assertThrows(() => validateQuoteInput({ text: "x".repeat(501) }), ApiError);
  assertEquals(validateQuoteInput({ text: "😀".repeat(500) }).text.length, 1000);
  assertThrows(() => validateQuoteInput({ text: "a", author: "x".repeat(201) }), ApiError);
  assertThrows(() => validateQuoteInput({ text: "a", author: 1 }), ApiError);
  assertThrows(() => validateQuoteInput(null), ApiError);
  assertEquals(validateQuotePatch({ day: null }), { day: null });
  assertThrows(() => validateQuotePatch({ text: "  " }), ApiError);
  assertThrows(() => validateQuotePatch({ other: 1 }), ApiError);
});

// Loves --------------------------------------------------------------------------

Deno.test("loves: love is idempotent, list is newest first, unlove is idempotent", async () => {
  const { db, loves } = setup();
  const [q1, q2] = seedDays(db, "2026-10-16", 2);

  let res = await loves(req("POST", "quote-loves", { quoteId: q1.id }, as("alice")));
  assertEquals(res.status, 200);
  const first = await body(res);
  assertEquals(first.id, q1.id);
  assertEquals(first.loved, true);

  res = await loves(req("POST", "quote-loves", { quoteId: q1.id }, as("alice")));
  assertEquals((await body(res)).lovedAt, first.lovedAt); // unchanged
  await loves(req("POST", "quote-loves", { quoteId: q2.id }, as("alice")));

  let list = await body(await loves(req("GET", "quote-loves", undefined, as("alice"))));
  assertEquals(list.items.map((i: { id: string }) => i.id), [q2.id, q1.id]);
  assert(list.items.every((i: { loved: boolean; lovedAt: string }) => i.loved && i.lovedAt));

  // Bob sees none of Alice's loves.
  list = await body(await loves(req("GET", "quote-loves", undefined, as("bob"))));
  assertEquals(list.items, []);

  for (let i = 0; i < 2; i++) {
    res = await loves(req("DELETE", `quote-loves?quoteId=${q1.id}`, undefined, as("alice")));
    assertEquals(res.status, 204);
  }
  list = await body(await loves(req("GET", "quote-loves", undefined, as("alice"))));
  assertEquals(list.items.map((i: { id: string }) => i.id), [q2.id]);
});

Deno.test("loves: errors", async () => {
  const { loves } = setup();
  const unknown = "00000000-0000-4000-8000-0000000000ff";
  assertEquals((await loves(req("GET", "quote-loves"))).status, 401);
  let res = await loves(req("POST", "quote-loves", { quoteId: unknown }, as("alice")));
  assertEquals(res.status, 404);
  res = await loves(req("POST", "quote-loves", { quoteId: "nope" }, as("alice")));
  assertEquals(res.status, 400);
  res = await loves(req("POST", "quote-loves", "not json", as("alice")));
  assertEquals(res.status, 400);
  res = await loves(req("DELETE", "quote-loves", undefined, as("alice")));
  assertEquals(res.status, 400);
  res = await loves(req("DELETE", `quote-loves?quoteId=${unknown}`, undefined, as("alice")));
  assertEquals(res.status, 204);
  res = await loves(req("GET", "quote-loves", undefined, as("service")));
  assertEquals(res.status, 403);
  res = await loves(req("PUT", "quote-loves", undefined, as("alice")));
  assertEquals(res.status, 405);
});
