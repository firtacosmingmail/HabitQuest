import { invalidInput } from "./errors.ts";
import type { CheckIn, GameState, Habit, JsonObject } from "./types.ts";

const ISO_TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,9})?)?(Z|[+-]\d{2}(:?\d{2})?)$/;
const DATE = /^(\d{4})-(\d{2})-(\d{2})$/;
const HH_MM = /^([01]\d|2[0-3]):[0-5]\d$/;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export const MAX_ID_LENGTH = 200;
export const MAX_NAME_LENGTH = 200;
export const MAX_EMOJI_LENGTH = 32;
export const MAX_DISPLAY_NAME_LENGTH = 100;
export const MAX_BATCH_ITEMS = 500;
export const MAX_ARGB = 0xffffffff;

export function isPlainObject(v: unknown): v is JsonObject {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

/** Truncates fractional seconds to milliseconds so `Date` parses reliably. */
function truncateFraction(s: string): string {
  return s.replace(/(\.\d{3})\d+/, "$1");
}

/** ISO-8601 timestamp with a time zone (Z or ±hh:mm). */
export function isIsoTimestamp(v: unknown): v is string {
  return typeof v === "string" && ISO_TIMESTAMP.test(v) &&
    !Number.isNaN(Date.parse(truncateFraction(v)));
}

/** Normalises any accepted timestamp to `yyyy-MM-ddTHH:mm:ss.SSSZ` (UTC). */
export function toIsoMillis(v: string): string {
  const ms = Date.parse(truncateFraction(v));
  if (Number.isNaN(ms)) throw invalidInput(`Invalid timestamp: ${v}`);
  return new Date(ms).toISOString();
}

/** Epoch milliseconds of an accepted timestamp. */
export function timestampMillis(v: string): number {
  return Date.parse(truncateFraction(v));
}

/** A real calendar date in `yyyy-MM-dd` form. */
export function isDate(v: unknown): v is string {
  if (typeof v !== "string") return false;
  const m = DATE.exec(v);
  if (!m) return false;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const dt = new Date(Date.UTC(y, mo - 1, d));
  return dt.getUTCFullYear() === y && dt.getUTCMonth() === mo - 1 &&
    dt.getUTCDate() === d;
}

export function isReminderTime(v: unknown): v is string {
  return typeof v === "string" && HH_MM.test(v);
}

function requireString(
  body: JsonObject,
  field: string,
  opts: { min?: number; max: number },
): string {
  const v = body[field];
  if (typeof v !== "string") throw invalidInput(`${field} must be a string`);
  const len = [...v].length;
  if (len < (opts.min ?? 0)) throw invalidInput(`${field} must not be empty`);
  if (len > opts.max) {
    throw invalidInput(`${field} must be at most ${opts.max} characters`);
  }
  return v;
}

function requireTimestamp(body: JsonObject, field: string): string {
  const v = body[field];
  if (!isIsoTimestamp(v)) {
    throw invalidInput(`${field} must be an ISO-8601 timestamp with a time zone`);
  }
  return toIsoMillis(v);
}

function optionalTimestamp(body: JsonObject, field: string): string | null {
  const v = body[field];
  if (v === undefined || v === null) return null;
  return requireTimestamp(body, field);
}

function requireBool(body: JsonObject, field: string): boolean {
  const v = body[field];
  if (typeof v !== "boolean") throw invalidInput(`${field} must be a boolean`);
  return v;
}

/** Resolves the resource id from the body and/or the path. */
function resolveId(body: JsonObject, pathId: string | undefined): string {
  const bodyId = body.id;
  if (bodyId !== undefined && typeof bodyId !== "string") {
    throw invalidInput("id must be a string");
  }
  if (pathId !== undefined && bodyId !== undefined && bodyId !== pathId) {
    throw invalidInput("id in the body does not match the id in the path");
  }
  const id = (pathId ?? bodyId) as string | undefined;
  if (id === undefined) throw invalidInput("id is required");
  const len = [...id].length;
  if (len < 1 || len > MAX_ID_LENGTH) {
    throw invalidInput(`id must be 1 to ${MAX_ID_LENGTH} characters`);
  }
  return id;
}

/** Validates a Habit body (PUT/POST/batch item). */
export function validateHabit(body: unknown, pathId?: string): Habit {
  if (!isPlainObject(body)) throw invalidInput("Habit must be a JSON object");
  const id = resolveId(body, pathId);
  const name = requireString(body, "name", { min: 1, max: MAX_NAME_LENGTH });
  if (name.trim() === "") throw invalidInput("name must not be blank");
  const emoji = body.emoji === undefined
    ? ""
    : requireString(body, "emoji", { max: MAX_EMOJI_LENGTH });
  const color = body.color;
  if (
    typeof color !== "number" || !Number.isInteger(color) || color < 0 ||
    color > MAX_ARGB
  ) {
    throw invalidInput("color must be an integer ARGB value (0..4294967295)");
  }
  if (!isPlainObject(body.schedule)) {
    throw invalidInput("schedule must be a JSON object");
  }
  const reminder = body.reminderTime;
  if (reminder !== undefined && reminder !== null && !isReminderTime(reminder)) {
    throw invalidInput('reminderTime must be "HH:mm" or null');
  }
  return {
    id,
    name,
    emoji,
    color,
    schedule: body.schedule,
    reminderTime: (reminder as string | null | undefined) ?? null,
    createdAt: requireTimestamp(body, "createdAt"),
    archived: body.archived === undefined ? false : requireBool(body, "archived"),
    updatedAt: requireTimestamp(body, "updatedAt"),
    deletedAt: optionalTimestamp(body, "deletedAt"),
  };
}

/** The id of a check-in: `<habitId>_<yyyy-MM-dd>`. */
export function checkInId(habitId: string, date: string): string {
  return `${habitId}_${date}`;
}

/** Validates a CheckIn body (PUT/POST/batch item). */
export function validateCheckIn(body: unknown, pathId?: string): CheckIn {
  if (!isPlainObject(body)) throw invalidInput("CheckIn must be a JSON object");
  const habitId = requireString(body, "habitId", {
    min: 1,
    max: MAX_ID_LENGTH,
  });
  if (!isDate(body.date)) throw invalidInput('date must be "yyyy-MM-dd"');
  const date = body.date;
  const expected = checkInId(habitId, date);
  const withId = body.id === undefined && pathId === undefined ? { ...body, id: expected } : body;
  const id = resolveId(withId, pathId);
  if (id !== expected) {
    throw invalidInput(`id must be "<habitId>_<date>" (expected "${expected}")`);
  }
  return {
    id,
    habitId,
    date,
    completed: requireBool(body, "completed"),
    updatedAt: requireTimestamp(body, "updatedAt"),
    deletedAt: optionalTimestamp(body, "deletedAt"),
  };
}

/** Validates a GameState body. */
export function validateGameState(body: unknown): GameState {
  if (!isPlainObject(body)) {
    throw invalidInput("GameState must be a JSON object");
  }
  if (!isPlainObject(body.state)) {
    throw invalidInput("state must be a JSON object");
  }
  return { state: body.state, updatedAt: requireTimestamp(body, "updatedAt") };
}

/** Validates `{"items":[...]}` with a per-item validator. */
export function validateBatch<T>(
  body: unknown,
  validateItem: (item: unknown) => T,
): T[] {
  if (!isPlainObject(body) || !Array.isArray(body.items)) {
    throw invalidInput('Body must be {"items":[...]}');
  }
  if (body.items.length > MAX_BATCH_ITEMS) {
    throw invalidInput(`At most ${MAX_BATCH_ITEMS} items per batch`);
  }
  return body.items.map((item, i) => {
    try {
      return validateItem(item);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      throw invalidInput(`items[${i}]: ${msg}`);
    }
  });
}

/** Parses the optional `since` query parameter. */
export function parseSince(v: string | null): string | null {
  if (v === null || v === "") return null;
  if (!isIsoTimestamp(v)) {
    throw invalidInput("since must be an ISO-8601 timestamp with a time zone");
  }
  return toIsoMillis(v);
}

/** Parses the optional `updatedAt` query parameter of DELETE. */
export function parseUpdatedAtParam(v: string | null): string | null {
  if (v === null || v === "") return null;
  if (!isIsoTimestamp(v)) {
    throw invalidInput("updatedAt must be an ISO-8601 timestamp with a time zone");
  }
  return toIsoMillis(v);
}

export interface Credentials {
  email: string;
  password: string;
}

/** Validates `{email, password}` (login, register). */
export function validateCredentials(body: JsonObject): Credentials {
  const email = body.email;
  if (typeof email !== "string" || !EMAIL.test(email.trim())) {
    throw invalidInput("email must be a valid email address");
  }
  const password = body.password;
  if (typeof password !== "string" || password.length === 0) {
    throw invalidInput("password is required");
  }
  if (password.length > 72) {
    throw invalidInput("password must be at most 72 characters");
  }
  return { email: email.trim().toLowerCase(), password };
}

export interface Registration extends Credentials {
  displayName: string | null;
}

export function validateRegistration(body: JsonObject): Registration {
  const creds = validateCredentials(body);
  const dn = body.displayName;
  if (dn !== undefined && dn !== null && typeof dn !== "string") {
    throw invalidInput("displayName must be a string");
  }
  const displayName = typeof dn === "string" && dn.trim() !== "" ? dn.trim() : null;
  if (displayName && [...displayName].length > MAX_DISPLAY_NAME_LENGTH) {
    throw invalidInput(
      `displayName must be at most ${MAX_DISPLAY_NAME_LENGTH} characters`,
    );
  }
  return { ...creds, displayName };
}

export function validateRefresh(body: JsonObject): string {
  const t = body.refreshToken;
  if (typeof t !== "string" || t.trim() === "") {
    throw invalidInput("refreshToken is required");
  }
  return t.trim();
}
