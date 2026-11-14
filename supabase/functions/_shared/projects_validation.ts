/**
 * Validation of the Projects resources (docs/PROJECTS.md, supabase/API.md
 * "Projects"). Same conventions as the habit/check-in validators in
 * validation.ts: camelCase bodies, timestamps normalised to UTC milliseconds,
 * `yyyy-MM-dd` dates, `400 invalid_input` on any problem.
 *
 * Ids are UUIDs, accepted in any case and lower-cased (Postgres `uuid`
 * returns them lower case). The overlap rule between consistent actions is an
 * app rule and is NOT checked here.
 */
import { invalidInput } from "./errors.ts";
import type {
  ActionRecurrence,
  ConsistentAction,
  JsonObject,
  PlanTask,
  Project,
  SessionMark,
  Target,
  TargetStatus,
} from "./types.ts";
import {
  isDate,
  isIsoTimestamp,
  isPlainObject,
  isReminderTime,
  isUuid,
  MAX_NAME_LENGTH,
  toIsoMillis,
} from "./validation.ts";

export const TARGET_STATUSES: readonly TargetStatus[] = ["notStarted", "inProgress", "done"];
/** Postgres `integer` range for plan task positions. */
export const MIN_POSITION = -2147483648;
export const MAX_POSITION = 2147483647;

function timestamp(body: JsonObject, field: string): string {
  const v = body[field];
  if (!isIsoTimestamp(v)) {
    throw invalidInput(`${field} must be an ISO-8601 timestamp with a time zone`);
  }
  return toIsoMillis(v);
}

function optionalTimestamp(body: JsonObject, field: string): string | null {
  const v = body[field];
  return v === undefined || v === null ? null : timestamp(body, field);
}

function bool(body: JsonObject, field: string, fallback?: boolean): boolean {
  const v = body[field];
  if (v === undefined && fallback !== undefined) return fallback;
  if (typeof v !== "boolean") throw invalidInput(`${field} must be a boolean`);
  return v;
}

function date(body: JsonObject, field: string): string {
  const v = body[field];
  if (!isDate(v)) throw invalidInput(`${field} must be a date "yyyy-MM-dd"`);
  return v;
}

function optionalDate(body: JsonObject, field: string): string | null {
  const v = body[field];
  if (v === undefined || v === null) return null;
  if (!isDate(v)) throw invalidInput(`${field} must be a date "yyyy-MM-dd" or null`);
  return v;
}

/** Non-blank string, at most MAX_NAME_LENGTH characters (stored as sent). */
function text(body: JsonObject, field: string): string {
  const v = body[field];
  if (typeof v !== "string") throw invalidInput(`${field} must be a string`);
  if (v.trim() === "") throw invalidInput(`${field} must not be blank`);
  if ([...v].length > MAX_NAME_LENGTH) {
    throw invalidInput(`${field} must be at most ${MAX_NAME_LENGTH} characters`);
  }
  return v;
}

function uuidField(body: JsonObject, field: string): string {
  const v = body[field];
  if (!isUuid(v)) throw invalidInput(`${field} must be a UUID`);
  return v.toLowerCase();
}

/** A UUID path segment (lower-cased) or 400. */
export function parseUuidId(id: string): string {
  if (!isUuid(id)) throw invalidInput("id must be a UUID");
  return id.toLowerCase();
}

/** Resolves the uuid id from the body and/or the path (case-insensitive match). */
function resolveUuid(body: JsonObject, pathId: string | undefined): string {
  const bodyId = body.id;
  if (bodyId !== undefined && !isUuid(bodyId)) throw invalidInput("id must be a UUID");
  const path = pathId === undefined ? undefined : parseUuidId(pathId);
  const fromBody = bodyId === undefined ? undefined : (bodyId as string).toLowerCase();
  if (path !== undefined && fromBody !== undefined && path !== fromBody) {
    throw invalidInput("id in the body does not match the id in the path");
  }
  const id = path ?? fromBody;
  if (id === undefined) throw invalidInput("id is required");
  return id;
}

function requireObject(body: unknown, what: string): JsonObject {
  if (!isPlainObject(body)) throw invalidInput(`${what} must be a JSON object`);
  return body;
}

export function validateProject(body: unknown, pathId?: string): Project {
  const b = requireObject(body, "Project");
  return {
    id: resolveUuid(b, pathId),
    name: text(b, "name"),
    archived: bool(b, "archived", false),
    createdAt: timestamp(b, "createdAt"),
    updatedAt: timestamp(b, "updatedAt"),
    deletedAt: optionalTimestamp(b, "deletedAt"),
  };
}

export function validateTarget(body: unknown, pathId?: string): Target {
  const b = requireObject(body, "Target");
  const status = b.status ?? "notStarted";
  if (!TARGET_STATUSES.includes(status as TargetStatus)) {
    throw invalidInput(`status must be one of ${TARGET_STATUSES.join(", ")}`);
  }
  return {
    id: resolveUuid(b, pathId),
    projectId: uuidField(b, "projectId"),
    title: text(b, "title"),
    deadline: date(b, "deadline"),
    status: status as TargetStatus,
    createdAt: timestamp(b, "createdAt"),
    updatedAt: timestamp(b, "updatedAt"),
    deletedAt: optionalTimestamp(b, "deletedAt"),
  };
}

export function validatePlanTask(body: unknown, pathId?: string): PlanTask {
  const b = requireObject(body, "PlanTask");
  const position = b.position ?? 0;
  if (
    typeof position !== "number" || !Number.isInteger(position) ||
    position < MIN_POSITION || position > MAX_POSITION
  ) {
    throw invalidInput("position must be a 32-bit integer");
  }
  return {
    id: resolveUuid(b, pathId),
    targetId: uuidField(b, "targetId"),
    title: text(b, "title"),
    deliveryDate: optionalDate(b, "deliveryDate"),
    done: bool(b, "done", false),
    position,
    createdAt: timestamp(b, "createdAt"),
    updatedAt: timestamp(b, "updatedAt"),
    deletedAt: optionalTimestamp(b, "deletedAt"),
  };
}

/** Non-empty, strictly ascending integers in [min, max]. */
function dayList(v: unknown, field: string, min: number, max: number): number[] {
  if (!Array.isArray(v) || v.length === 0) {
    throw invalidInput(`recurrence.${field} must be a non-empty array`);
  }
  v.forEach((n, i) => {
    if (typeof n !== "number" || !Number.isInteger(n) || n < min || n > max) {
      throw invalidInput(`recurrence.${field} must contain integers ${min}..${max}`);
    }
    if (i > 0 && n <= v[i - 1]) {
      throw invalidInput(`recurrence.${field} must be sorted ascending without duplicates`);
    }
  });
  return [...v] as number[];
}

/**
 * `{"type":"weekly","weekdays":[1..7]}` (ISO, 1 = Monday) or
 * `{"type":"monthly","monthDays":[1..31]}`. Stored normalised (other keys
 * dropped).
 */
export function validateRecurrence(v: unknown): ActionRecurrence {
  if (!isPlainObject(v)) throw invalidInput("recurrence must be a JSON object");
  switch (v.type) {
    case "weekly":
      return { type: "weekly", weekdays: dayList(v.weekdays, "weekdays", 1, 7) };
    case "monthly":
      return { type: "monthly", monthDays: dayList(v.monthDays, "monthDays", 1, 31) };
    default:
      throw invalidInput('recurrence.type must be "weekly" or "monthly"');
  }
}

export function validateConsistentAction(body: unknown, pathId?: string): ConsistentAction {
  const b = requireObject(body, "ConsistentAction");
  const { startTime, endTime } = b;
  if (!isReminderTime(startTime)) throw invalidInput('startTime must be "HH:mm"');
  if (!isReminderTime(endTime)) throw invalidInput('endTime must be "HH:mm"');
  if (endTime <= startTime) {
    throw invalidInput("endTime must be after startTime (no block across midnight)");
  }
  return {
    id: resolveUuid(b, pathId),
    targetId: uuidField(b, "targetId"),
    startTime,
    endTime,
    recurrence: validateRecurrence(b.recurrence),
    startDate: optionalDate(b, "startDate"),
    createdAt: timestamp(b, "createdAt"),
    updatedAt: timestamp(b, "updatedAt"),
    deletedAt: optionalTimestamp(b, "deletedAt"),
  };
}

/** The key of a session mark: `<actionId>|<yyyy-MM-dd>` (lower-case uuid). */
export function sessionMarkId(actionId: string, date: string): string {
  return `${actionId.toLowerCase()}|${date}`;
}

/** Splits `<actionId>|<yyyy-MM-dd>` or throws 400. */
export function parseSessionMarkId(id: string): { actionId: string; date: string } {
  const i = id.lastIndexOf("|");
  const actionId = i < 0 ? "" : id.slice(0, i);
  const d = i < 0 ? "" : id.slice(i + 1);
  if (!isUuid(actionId) || !isDate(d)) {
    throw invalidInput('id must be "<actionId>|<yyyy-MM-dd>"');
  }
  return { actionId: actionId.toLowerCase(), date: d };
}

export function validateSessionMark(body: unknown, pathId?: string): SessionMark {
  const b = requireObject(body, "SessionMark");
  const actionId = uuidField(b, "actionId");
  const d = date(b, "date");
  const expected = sessionMarkId(actionId, d);
  for (const given of [b.id, pathId]) {
    if (given === undefined) continue;
    if (typeof given !== "string") throw invalidInput("id must be a string");
    const key = parseSessionMarkId(given);
    if (sessionMarkId(key.actionId, key.date) !== expected) {
      throw invalidInput(`id must be "<actionId>|<date>" (expected "${expected}")`);
    }
  }
  return {
    id: expected,
    actionId,
    date: d,
    attended: bool(b, "attended"),
    updatedAt: timestamp(b, "updatedAt"),
    deletedAt: optionalTimestamp(b, "deletedAt"),
  };
}
