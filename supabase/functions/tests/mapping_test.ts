import { assert, assertEquals } from "jsr:@std/assert@1";
import { mapDbError } from "../_shared/errors.ts";
import { shouldApply, tombstone } from "../_shared/lww.ts";
import {
  checkInToRow,
  habitToRow,
  rowToCheckIn,
  rowToGameState,
  rowToHabit,
  toSession,
} from "../_shared/mapping.ts";
import { subPath } from "../_shared/http.ts";
import { validateCheckIn, validateHabit } from "../_shared/validation.ts";
import { checkInBody, habitBody } from "./fakes.ts";

Deno.test("habit JSON ↔ row round-trip", () => {
  const h = validateHabit(habitBody());
  const row = habitToRow(h);
  assertEquals(row.reminder_time, "08:30");
  assertEquals(row.color, 0xff2196f3);
  assertEquals(rowToHabit(row), h);
});

Deno.test("rowToHabit normalises Postgres timestamps and bigint", () => {
  const h = rowToHabit({
    user_id: "u",
    id: "h1",
    name: "n",
    emoji: "",
    // PostgREST may return bigint as a number; be lenient with strings too.
    color: "4280391411" as unknown as number,
    schedule: { type: "daily" },
    reminder_time: null,
    created_at: "2026-10-01T08:00:00+00:00",
    archived: false,
    updated_at: "2026-10-07T09:15:00.123456+00:00",
    deleted_at: "2026-10-07T11:15:00+02:00",
    server_updated_at: "2026-10-07T09:15:01.5+00:00",
  });
  assertEquals(h.color, 4280391411);
  assertEquals(h.createdAt, "2026-10-01T08:00:00.000Z");
  assertEquals(h.updatedAt, "2026-10-07T09:15:00.123Z");
  assertEquals(h.deletedAt, "2026-10-07T09:15:00.000Z");
  assert(!("serverUpdatedAt" in h));
  assert(!("userId" in h));
});

Deno.test("check-in JSON ↔ row round-trip", () => {
  const c = validateCheckIn(checkInBody());
  const row = checkInToRow(c);
  assertEquals(row.habit_id, "h1");
  assertEquals(rowToCheckIn(row), c);
});

Deno.test("game state row → JSON", () => {
  assertEquals(rowToGameState({ state: { a: 1 }, updated_at: "2026-10-07T09:15:00+00:00" }), {
    state: { a: 1 },
    updatedAt: "2026-10-07T09:15:00.000Z",
  });
});

Deno.test("toSession uses expires_at, falls back to expires_in", () => {
  const s = {
    access_token: "a",
    refresh_token: "r",
    user: { id: "u", email: "e@x.io" },
  };
  assertEquals(toSession({ ...s, expires_at: 100.7 }).expiresAt, 100);
  assertEquals(toSession({ ...s, expires_in: 3600 }, 1000).expiresAt, 4600);
  assertEquals(toSession({ ...s, user: { id: "u" } }).user, { id: "u", email: null });
});

Deno.test("LWW: strictly newer wins; equal and older lose; no row → apply", () => {
  const stored = { updatedAt: "2026-10-07T09:15:00.000Z" };
  assert(shouldApply("2026-10-07T09:15:00.001Z", stored));
  assert(!shouldApply("2026-10-07T09:15:00.000Z", stored));
  assert(!shouldApply("2026-10-07T11:15:00+02:00", stored)); // same instant
  assert(!shouldApply("2026-10-07T09:14:59.999Z", stored));
  assert(shouldApply("2000-01-01T00:00:00Z", null));
  const t = tombstone({ updatedAt: "a", deletedAt: null as string | null, x: 1 }, "b");
  assertEquals(t, { updatedAt: "b", deletedAt: "b", x: 1 });
});

Deno.test("mapDbError", () => {
  assertEquals(mapDbError({ code: "23503" }).code, "habit_not_found");
  assertEquals(mapDbError({ code: "23503" }).status, 409);
  assertEquals(mapDbError({ code: "23514", message: "check" }).code, "invalid_input");
  assertEquals(mapDbError({ code: "PGRST301" }).status, 401);
  assertEquals(mapDbError({ code: "XX000" }).status, 500);
});

Deno.test("subPath handles hosted and local URL shapes", () => {
  assertEquals(subPath(new URL("http://x/functions/v1/habits/a"), "habits"), ["a"]);
  assertEquals(subPath(new URL("http://x/habits/a/"), "habits"), ["a"]);
  assertEquals(subPath(new URL("http://x/habits"), "habits"), []);
  assertEquals(subPath(new URL("http://x/check-ins/h%2F1_2026-10-07"), "check-ins"), [
    "h/1_2026-10-07",
  ]);
});
