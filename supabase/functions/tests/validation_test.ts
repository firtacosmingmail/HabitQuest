import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import { ApiError } from "../_shared/errors.ts";
import {
  isDate,
  isIsoTimestamp,
  isReminderTime,
  parseSince,
  toIsoMillis,
  validateBatch,
  validateCheckIn,
  validateCredentials,
  validateGameState,
  validateHabit,
  validateRefresh,
  validateRegistration,
} from "../_shared/validation.ts";
import { checkInBody, habitBody } from "./fakes.ts";

function assertInvalid(fn: () => unknown, code = "invalid_input") {
  const e = assertThrows(fn, ApiError);
  assertEquals(e.code, code);
  assertEquals(e.status, 400);
}

Deno.test("timestamps: accepts ISO with zone, rejects others", () => {
  assert(isIsoTimestamp("2026-10-07T09:15:00.000Z"));
  assert(isIsoTimestamp("2026-10-07T09:15:00Z"));
  assert(isIsoTimestamp("2026-10-07T11:15:00.123456+02:00"));
  assert(!isIsoTimestamp("2026-10-07T09:15:00")); // no zone
  assert(!isIsoTimestamp("2026-10-07"));
  assert(!isIsoTimestamp("yesterday"));
  assert(!isIsoTimestamp(123));
});

Deno.test("toIsoMillis normalises to UTC with milliseconds", () => {
  assertEquals(toIsoMillis("2026-10-07T11:15:00+02:00"), "2026-10-07T09:15:00.000Z");
  assertEquals(toIsoMillis("2026-10-07T09:15:00.123456+00:00"), "2026-10-07T09:15:00.123Z");
});

Deno.test("dates and reminder times", () => {
  assert(isDate("2026-02-28"));
  assert(isDate("2024-02-29"));
  assert(!isDate("2026-02-29"));
  assert(!isDate("2026-13-01"));
  assert(!isDate("2026-1-01"));
  assert(isReminderTime("00:00"));
  assert(isReminderTime("23:59"));
  assert(!isReminderTime("24:00"));
  assert(!isReminderTime("8:30"));
});

Deno.test("validateHabit: valid body round-trips and normalises", () => {
  const h = validateHabit(habitBody({ updatedAt: "2026-10-07T11:15:00+02:00" }));
  assertEquals(h.id, "h1");
  assertEquals(h.color, 0xff2196f3);
  assertEquals(h.updatedAt, "2026-10-07T09:15:00.000Z");
  assertEquals(h.deletedAt, null);
  assertEquals(h.schedule, { type: "daily" });
});

Deno.test("validateHabit: defaults for optional fields", () => {
  const b = habitBody();
  delete (b as Record<string, unknown>).reminderTime;
  delete (b as Record<string, unknown>).deletedAt;
  delete (b as Record<string, unknown>).archived;
  const h = validateHabit(b);
  assertEquals(h.reminderTime, null);
  assertEquals(h.deletedAt, null);
  assertEquals(h.archived, false);
});

Deno.test("validateHabit: path id wins when body has none; mismatch rejected", () => {
  const b = habitBody();
  delete (b as Record<string, unknown>).id;
  assertEquals(validateHabit(b, "from-path").id, "from-path");
  assertInvalid(() => validateHabit(habitBody({ id: "a" }), "b"));
  assertInvalid(() => validateHabit(b)); // no id at all
});

Deno.test("validateHabit: rejects bad fields", () => {
  assertInvalid(() => validateHabit(null));
  assertInvalid(() => validateHabit([]));
  assertInvalid(() => validateHabit(habitBody({ name: "" })));
  assertInvalid(() => validateHabit(habitBody({ name: "   " })));
  assertInvalid(() => validateHabit(habitBody({ color: -1 })));
  assertInvalid(() => validateHabit(habitBody({ color: 0x100000000 })));
  assertInvalid(() => validateHabit(habitBody({ color: 1.5 })));
  assertInvalid(() => validateHabit(habitBody({ color: "red" })));
  assertInvalid(() => validateHabit(habitBody({ schedule: "daily" })));
  assertInvalid(() => validateHabit(habitBody({ schedule: [] })));
  assertInvalid(() => validateHabit(habitBody({ reminderTime: "25:00" })));
  assertInvalid(() => validateHabit(habitBody({ updatedAt: undefined })));
  assertInvalid(() => validateHabit(habitBody({ createdAt: "nope" })));
  assertInvalid(() => validateHabit(habitBody({ deletedAt: "nope" })));
  assertInvalid(() => validateHabit(habitBody({ archived: "yes" })));
  assertInvalid(() => validateHabit(habitBody({ id: "x".repeat(201) })));
});

Deno.test("validateCheckIn: id must be <habitId>_<date>", () => {
  assertEquals(validateCheckIn(checkInBody()).id, "h1_2026-10-07");
  const noId = checkInBody();
  delete (noId as Record<string, unknown>).id;
  assertEquals(validateCheckIn(noId).id, "h1_2026-10-07");
  assertEquals(validateCheckIn(noId, "h1_2026-10-07").id, "h1_2026-10-07");
  assertInvalid(() => validateCheckIn(checkInBody({ id: "h1_2026-10-08" })));
  assertInvalid(() => validateCheckIn(noId, "h2_2026-10-07"));
});

Deno.test("validateCheckIn: rejects bad fields", () => {
  assertInvalid(() => validateCheckIn(checkInBody({ date: "2026-10-32" })));
  assertInvalid(() => validateCheckIn(checkInBody({ completed: 1 })));
  assertInvalid(() => validateCheckIn(checkInBody({ habitId: "" })));
  assertInvalid(() => validateCheckIn(checkInBody({ updatedAt: null })));
});

Deno.test("validateGameState", () => {
  const gs = validateGameState({ state: { xp: 5 }, updatedAt: "2026-10-07T09:15:00Z" });
  assertEquals(gs, { state: { xp: 5 }, updatedAt: "2026-10-07T09:15:00.000Z" });
  assertInvalid(() => validateGameState({ state: [], updatedAt: "2026-10-07T09:15:00Z" }));
  assertInvalid(() => validateGameState({ state: {} }));
});

Deno.test("validateBatch names the failing index", () => {
  const e = assertThrows(
    () => validateBatch({ items: [habitBody(), habitBody({ name: "" })] }, (i) => validateHabit(i)),
    ApiError,
  );
  assert(e.message.startsWith("items[1]:"));
  assertInvalid(() => validateBatch({ items: "x" }, validateHabit));
  assertInvalid(() => validateBatch({ items: new Array(501).fill(habitBody()) }, validateHabit));
  assertEquals(validateBatch({ items: [] }, validateHabit), []);
});

Deno.test("parseSince", () => {
  assertEquals(parseSince(null), null);
  assertEquals(parseSince(""), null);
  assertEquals(parseSince("2026-10-07T09:15:00Z"), "2026-10-07T09:15:00.000Z");
  assertInvalid(() => parseSince("last week"));
});

Deno.test("credentials, registration and refresh validation", () => {
  assertEquals(validateCredentials({ email: " A@B.co ", password: "x" }), {
    email: "a@b.co",
    password: "x",
  });
  assertInvalid(() => validateCredentials({ email: "nope", password: "x" }));
  assertInvalid(() => validateCredentials({ email: "a@b.co" }));
  assertInvalid(() => validateCredentials({ email: "a@b.co", password: "x".repeat(73) }));
  assertEquals(
    validateRegistration({ email: "a@b.co", password: "x", displayName: " Ann " }).displayName,
    "Ann",
  );
  assertEquals(validateRegistration({ email: "a@b.co", password: "x" }).displayName, null);
  assertInvalid(() => validateRegistration({ email: "a@b.co", password: "x", displayName: 3 }));
  assertInvalid(() =>
    validateRegistration({ email: "a@b.co", password: "x", displayName: "x".repeat(101) })
  );
  assertEquals(validateRefresh({ refreshToken: "abc" }), "abc");
  assertInvalid(() => validateRefresh({}));
});
