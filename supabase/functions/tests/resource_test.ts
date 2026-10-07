import { assert, assertEquals } from "jsr:@std/assert@1";
import { withHttp } from "../_shared/http.ts";
import { checkInsSpec, habitsSpec, handleResource } from "../_shared/resource.ts";
import type { CheckIn, Habit } from "../_shared/types.ts";
import { checkInBody, habitBody, habitMustExist, MemoryStore, req } from "./fakes.ts";

function setup() {
  const habits = new MemoryStore<Habit>();
  const checkIns = new MemoryStore<CheckIn>(habitMustExist(habits));
  return {
    habits,
    checkIns,
    h: withHttp((r) => handleResource(r, habitsSpec, habits)),
    c: withHttp((r) => handleResource(r, checkInsSpec, checkIns)),
  };
}

const later = "2026-10-08T00:00:00.000Z";
const earlier = "2026-10-01T00:00:00.000Z";

Deno.test("PUT inserts, then LWW: newer applies, older and equal do not", async () => {
  const { h } = setup();
  let res = await h(req("PUT", "habits/h1", habitBody()));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { item: habitBody(), applied: true });

  res = await h(req("PUT", "habits/h1", habitBody({ name: "Old", updatedAt: earlier })));
  let body = await res.json();
  assertEquals(body.applied, false);
  assertEquals(body.item.name, "Drink water"); // stored row returned

  res = await h(req("PUT", "habits/h1", habitBody({ name: "Same time" })));
  assertEquals((await res.json()).applied, false);

  res = await h(req("PUT", "habits/h1", habitBody({ name: "New", updatedAt: later })));
  body = await res.json();
  assertEquals(body.applied, true);
  assertEquals(body.item.name, "New");
});

Deno.test("POST /habits upserts with the id from the body", async () => {
  const { h, habits } = setup();
  const res = await h(req("POST", "habits", habitBody({ id: "from-body" })));
  assertEquals(res.status, 200);
  assertEquals((await res.json()).applied, true);
  assert(habits.rows.has("from-body"));
});

Deno.test("PUT with mismatched ids → 400 invalid_input", async () => {
  const { h } = setup();
  const res = await h(req("PUT", "habits/a", habitBody({ id: "b" })));
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error.code, "invalid_input");
});

Deno.test("invalid JSON body → 400 with contract error shape", async () => {
  const { h } = setup();
  const res = await h(req("PUT", "habits/h1", "{not json"));
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error.code, "invalid_input");
  assertEquals(typeof body.error.message, "string");
  assertEquals(res.headers.get("access-control-allow-origin"), "*");
});

Deno.test("GET /habits/<id> → item or 404 not_found; ids are URL-decoded", async () => {
  const { h } = setup();
  await h(req("PUT", "habits/a%20b", habitBody({ id: "a b" })));
  let res = await h(req("GET", "habits/a%20b"));
  assertEquals(res.status, 200);
  assertEquals((await res.json()).id, "a b");
  res = await h(req("GET", "habits/missing"));
  assertEquals(res.status, 404);
  assertEquals((await res.json()).error.code, "not_found");
});

Deno.test("GET /habits?since returns changed rows incl. tombstones and a cursor", async () => {
  const { h, habits } = setup();
  await h(req("PUT", "habits/h1", habitBody({ id: "h1" })));
  let res = await h(req("GET", "habits"));
  const all = await res.json();
  assertEquals(all.items.length, 1);
  assertEquals(typeof all.serverTime, "string");

  const cursor = new Date(habits.clock).toISOString();
  await h(req("PUT", "habits/h2", habitBody({ id: "h2" })));
  await h(req("DELETE", `habits/h1?updatedAt=${later}`));

  res = await h(req("GET", `habits?since=${encodeURIComponent(cursor)}`));
  const delta = await res.json();
  assertEquals(delta.items.map((i: Habit) => i.id), ["h2", "h1"]);
  assertEquals(delta.items[1].deletedAt, later);

  res = await h(req("GET", "habits?since=garbage"));
  assertEquals(res.status, 400);
});

Deno.test("DELETE soft-deletes with LWW; unknown id → 404", async () => {
  const { h } = setup();
  await h(req("PUT", "habits/h1", habitBody()));

  let res = await h(req("DELETE", `habits/h1?updatedAt=${earlier}`));
  let body = await res.json();
  assertEquals(body.applied, false);
  assertEquals(body.item.deletedAt, null);

  res = await h(req("DELETE", `habits/h1?updatedAt=${later}`));
  body = await res.json();
  assertEquals(res.status, 200);
  assertEquals(body.applied, true);
  assertEquals(body.item.deletedAt, later);
  assertEquals(body.item.updatedAt, later);

  // Still readable as a tombstone.
  res = await h(req("GET", "habits/h1"));
  assertEquals((await res.json()).deletedAt, later);

  // Undelete with a newer write.
  res = await h(req("PUT", "habits/h1", habitBody({ updatedAt: "2026-10-09T00:00:00.000Z" })));
  assertEquals((await res.json()).item.deletedAt, null);

  res = await h(req("DELETE", "habits/nope"));
  assertEquals(res.status, 404);
});

Deno.test("POST /habits/batch applies each item with LWW, in order", async () => {
  const { h } = setup();
  await h(req("PUT", "habits/h1", habitBody({ updatedAt: later })));
  const res = await h(req("POST", "habits/batch", {
    items: [habitBody({ id: "h1" }), habitBody({ id: "h2" })],
  }));
  assertEquals(res.status, 200);
  const { results } = await res.json();
  assertEquals(results.map((r: { id: string; applied: boolean }) => [r.id, r.applied]), [
    ["h1", false],
    ["h2", true],
  ]);
  assertEquals(results[0].item.updatedAt, later);
});

Deno.test("batch with an invalid item writes nothing", async () => {
  const { h, habits } = setup();
  const res = await h(req("POST", "habits/batch", {
    items: [habitBody({ id: "ok" }), habitBody({ id: "bad", color: "x" })],
  }));
  assertEquals(res.status, 400);
  assert((await res.json()).error.message.startsWith("items[1]"));
  assertEquals(habits.rows.size, 0);
});

Deno.test("unknown routes and methods", async () => {
  const { h } = setup();
  assertEquals((await h(req("GET", "habits/a/b"))).status, 404);
  assertEquals((await h(req("PATCH", "habits/a", habitBody()))).status, 405);
  assertEquals((await h(req("DELETE", "habits"))).status, 405);
  const pre = await h(req("OPTIONS", "habits"));
  assertEquals(pre.status, 200);
  assert(pre.headers.get("access-control-allow-headers")!.includes("apikey"));
  assert(pre.headers.get("access-control-allow-headers")!.includes("authorization"));
});

Deno.test("check-ins: upsert, habitId filter, habit must exist", async () => {
  const { h, c } = setup();
  let res = await c(req("PUT", "check-ins/h1_2026-10-07", checkInBody()));
  assertEquals(res.status, 409);
  assertEquals((await res.json()).error.code, "habit_not_found");

  await h(req("PUT", "habits/h1", habitBody({ id: "h1" })));
  await h(req("PUT", "habits/h2", habitBody({ id: "h2" })));
  res = await c(req("PUT", "check-ins/h1_2026-10-07", checkInBody()));
  assertEquals((await res.json()).applied, true);
  res = await c(req("POST", "check-ins/batch", {
    items: [checkInBody({ id: "h2_2026-10-07", habitId: "h2" })],
  }));
  assertEquals((await res.json()).results[0].applied, true);

  res = await c(req("GET", "check-ins?habitId=h2"));
  const list = await res.json();
  assertEquals(list.items.map((i: CheckIn) => i.id), ["h2_2026-10-07"]);

  res = await c(req("PUT", "check-ins/h1_2026-10-08", checkInBody()));
  assertEquals(res.status, 400);

  res = await c(req("DELETE", `check-ins/h1_2026-10-07?updatedAt=${later}`));
  const del = await res.json();
  assertEquals(del.applied, true);
  assertEquals(del.item.deletedAt, later);
  assertEquals(del.item.completed, true);
});
