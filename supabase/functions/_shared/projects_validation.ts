/**
 * Validation of the Projects resources (docs/PROJECTS.md, supabase/API.md
 * "Projects"). Same conventions as the habit/check-in validators in
 * validation.ts: camelCase bodies, timestamps normalised to UTC milliseconds,
 * `yyyy-MM-dd` dates, `400 invalid_input` on any problem.
 *
 * Ids are UUIDs, accepted in any case and lower-cased (Postgres `uuid`
 * returns them lower case). The overlap rule between time blocks is an app
 * rule and is NOT checked here.
 */
import { invalidInput } from "./errors.ts";
import type {
  BlockRecurrence,
  ConsistentAction,
  Goal,
  GoalStatus,
  JsonObject,
  PlanTask,
  Project,
  SessionMark,
  TimeBlock,
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

export const GOAL_STATUSES: readonly GoalStatus[] = ["notStarted", "inProgress", "done"];
/** Postgres `integer` range (plan task positions, consistent action sort orders). */
export const MIN_POSITION = -2147483648;
export const MAX_POSITION = 2147483647;
/** Max length of a time block label (like names and titles). */
export const MAX_LABEL_LENGTH = MAX_NAME_LENGTH;
/** Max length of a consistent action's text. */
export const MAX_ACTION_TEXT_LENGTH = 500;

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

/** Non-blank string, at most [max] characters (stored as sent). */
function text(body: JsonObject, field: string, max = MAX_NAME_LENGTH): string {
  const v = body[field];
  if (typeof v !== "string") throw invalidInput(`${field} must be a string`);
  if (v.trim() === "") throw invalidInput(`${field} must not be blank`);
  if ([...v].length > max) {
    throw invalidInput(`${field} must be at most ${max} characters`);
  }
  return v;
}

/** null when absent or null, else a non-blank string of at most [max] characters. */
function optionalText(body: JsonObject, field: string, max: number): string | null {
  const v = body[field];
  if (v === undefined || v === null) return null;
  if (typeof v !== "string") throw invalidInput(`${field} must be a string or null`);
  return text(body, field, max);
}

/** A 32-bit integer (Postgres `integer`), [fallback] when absent. */
function int32(body: JsonObject, field: string, fallback: number): number {
  const v = body[field] ?? fallback;
  if (
    typeof v !== "number" || !Number.isInteger(v) || v < MIN_POSITION || v > MAX_POSITION
  ) {
    throw invalidInput(`${field} must be a 32-bit integer`);
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

export function validateGoal(body: unknown, pathId?: string): Goal {
  const b = requireObject(body, "Goal");
  const status = b.status ?? "notStarted";
  if (!GOAL_STATUSES.includes(status as GoalStatus)) {
    throw invalidInput(`status must be one of ${GOAL_STATUSES.join(", ")}`);
  }
  return {
    id: resolveUuid(b, pathId),
    projectId: uuidField(b, "projectId"),
    title: text(b, "title"),
    deadline: date(b, "deadline"),
    status: status as GoalStatus,
    createdAt: timestamp(b, "createdAt"),
    updatedAt: timestamp(b, "updatedAt"),
    deletedAt: optionalTimestamp(b, "deletedAt"),
  };
}

export function validatePlanTask(body: unknown, pathId?: string): PlanTask {
  const b = requireObject(body, "PlanTask");
  const position = int32(b, "position", 0);
  return {
    id: resolveUuid(b, pathId),
    goalId: uuidField(b, "goalId"),
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
export function validateRecurrence(v: unknown): BlockRecurrence {
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

export function validateTimeBlock(body: unknown, pathId?: string): TimeBlock {
  const b = requireObject(body, "TimeBlock");
  const { startTime, endTime } = b;
  if (!isReminderTime(startTime)) throw invalidInput('startTime must be "HH:mm"');
  if (!isReminderTime(endTime)) throw invalidInput('endTime must be "HH:mm"');
  if (endTime <= startTime) {
    throw invalidInput("endTime must be after startTime (no block across midnight)");
  }
  const startDate = optionalDate(b, "startDate");
  const endDate = optionalDate(b, "endDate");
  if (startDate !== null && endDate !== null && endDate < startDate) {
    throw invalidInput("endDate must not be before startDate");
  }
  return {
    id: resolveUuid(b, pathId),
    projectId: uuidField(b, "projectId"),
    label: optionalText(b, "label", MAX_LABEL_LENGTH),
    startTime,
    endTime,
    recurrence: validateRecurrence(b.recurrence),
    startDate,
    endDate,
    createdAt: timestamp(b, "createdAt"),
    updatedAt: timestamp(b, "updatedAt"),
    deletedAt: optionalTimestamp(b, "deletedAt"),
  };
}

export function validateConsistentAction(body: unknown, pathId?: string): ConsistentAction {
  const b = requireObject(body, "ConsistentAction");
  return {
    id: resolveUuid(b, pathId),
    goalId: uuidField(b, "goalId"),
    text: text(b, "text", MAX_ACTION_TEXT_LENGTH),
    sortOrder: int32(b, "sortOrder", 0),
    createdAt: timestamp(b, "createdAt"),
    updatedAt: timestamp(b, "updatedAt"),
    deletedAt: optionalTimestamp(b, "deletedAt"),
  };
}

/** The key of a session mark: `<timeBlockId>|<yyyy-MM-dd>` (lower-case uuid). */
export function sessionMarkId(timeBlockId: string, date: string): string {
  return `${timeBlockId.toLowerCase()}|${date}`;
}

/** Splits `<timeBlockId>|<yyyy-MM-dd>` or throws 400. */
export function parseSessionMarkId(id: string): { timeBlockId: string; date: string } {
  const i = id.lastIndexOf("|");
  const timeBlockId = i < 0 ? "" : id.slice(0, i);
  const d = i < 0 ? "" : id.slice(i + 1);
  if (!isUuid(timeBlockId) || !isDate(d)) {
    throw invalidInput('id must be "<timeBlockId>|<yyyy-MM-dd>"');
  }
  return { timeBlockId: timeBlockId.toLowerCase(), date: d };
}

export function validateSessionMark(body: unknown, pathId?: string): SessionMark {
  const b = requireObject(body, "SessionMark");
  const timeBlockId = uuidField(b, "timeBlockId");
  const d = date(b, "date");
  const expected = sessionMarkId(timeBlockId, d);
  for (const given of [b.id, pathId]) {
    if (given === undefined) continue;
    if (typeof given !== "string") throw invalidInput("id must be a string");
    const key = parseSessionMarkId(given);
    if (sessionMarkId(key.timeBlockId, key.date) !== expected) {
      throw invalidInput(`id must be "<timeBlockId>|<date>" (expected "${expected}")`);
    }
  }
  return {
    id: expected,
    timeBlockId,
    date: d,
    attended: bool(b, "attended"),
    updatedAt: timestamp(b, "updatedAt"),
    deletedAt: optionalTimestamp(b, "deletedAt"),
  };
}
