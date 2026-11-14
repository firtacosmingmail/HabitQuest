/**
 * Generic HTTP handler for the LWW resources (`habits`, `check-ins`, and the
 * Projects resources `projects`, `targets`, `plan-tasks`,
 * `consistent-actions`, `session-marks`). The
 * storage is behind [ResourceStore] so the routing and validation can be
 * tested without a database (see tests/resource_test.ts).
 */
import { invalidInput, json, methodNotAllowed, notFound } from "./errors.ts";
import { readJsonObject, subPath } from "./http.ts";
import {
  parseSince,
  parseUpdatedAtParam,
  validateBatch,
  validateCheckIn,
  validateHabit,
} from "./validation.ts";
import {
  parseSessionMarkId,
  parseUuidId,
  validateConsistentAction,
  validatePlanTask,
  validateProject,
  validateSessionMark,
  validateTarget,
} from "./projects_validation.ts";
import type {
  BatchResult,
  CheckIn,
  ConsistentAction,
  Habit,
  PlanTask,
  Project,
  SessionMark,
  Target,
  WriteResult,
} from "./types.ts";

export interface ListQuery {
  since: string | null;
  /** Value of the spec's parent filter (`?habitId=`, `?projectId=`, ...), or null. */
  parentId: string | null;
}

export interface ResourceStore<T> {
  list(query: ListQuery): Promise<{ items: T[]; serverTime: string }>;
  get(id: string): Promise<T | null>;
  upsert(item: T): Promise<WriteResult<T>>;
  upsertMany(items: T[]): Promise<BatchResult<T>[]>;
  /** Returns null when the id does not exist. */
  softDelete(id: string, updatedAt: string | null): Promise<WriteResult<T> | null>;
}

export interface ResourceSpec<T> {
  /** Function name, also the first path segment. */
  name: string;
  validate(body: unknown, pathId?: string): T;
  /** Query parameter of the list's parent filter (e.g. `habitId`), if any. */
  parentFilter?: string;
  /** Checks/normalises the parent filter value (400 when malformed). */
  parseParent?(value: string): string;
  /** Checks/normalises a path id (400 when malformed); identity if absent. */
  parseId?(id: string): string;
}

export const habitsSpec: ResourceSpec<Habit> = {
  name: "habits",
  validate: validateHabit,
};

export const checkInsSpec: ResourceSpec<CheckIn> = {
  name: "check-ins",
  validate: validateCheckIn,
  parentFilter: "habitId",
};

const uuidParam = (field: string) => (v: string) => {
  try {
    return parseUuidId(v);
  } catch {
    throw invalidInput(`${field} must be a UUID`);
  }
};

export const projectsSpec: ResourceSpec<Project> = {
  name: "projects",
  validate: validateProject,
  parseId: parseUuidId,
};

export const targetsSpec: ResourceSpec<Target> = {
  name: "targets",
  validate: validateTarget,
  parentFilter: "projectId",
  parseParent: uuidParam("projectId"),
  parseId: parseUuidId,
};

export const planTasksSpec: ResourceSpec<PlanTask> = {
  name: "plan-tasks",
  validate: validatePlanTask,
  parentFilter: "targetId",
  parseParent: uuidParam("targetId"),
  parseId: parseUuidId,
};

export const consistentActionsSpec: ResourceSpec<ConsistentAction> = {
  name: "consistent-actions",
  validate: validateConsistentAction,
  parentFilter: "targetId",
  parseParent: uuidParam("targetId"),
  parseId: parseUuidId,
};

/** Path id: `<actionId>|<yyyy-MM-dd>` (send the `|` URL-encoded as `%7C`). */
export const sessionMarksSpec: ResourceSpec<SessionMark> = {
  name: "session-marks",
  validate: validateSessionMark,
  parentFilter: "actionId",
  parseParent: uuidParam("actionId"),
  parseId: (id) => {
    const k = parseSessionMarkId(id);
    return `${k.actionId}|${k.date}`;
  },
};

export async function handleResource<T>(
  req: Request,
  spec: ResourceSpec<T>,
  store: ResourceStore<T>,
): Promise<Response> {
  const url = new URL(req.url);
  const path = subPath(url, spec.name);
  const method = req.method.toUpperCase();

  if (path.length === 0) {
    switch (method) {
      case "GET": {
        const since = parseSince(url.searchParams.get("since"));
        const raw = spec.parentFilter ? (url.searchParams.get(spec.parentFilter) || null) : null;
        const parentId = raw !== null && spec.parseParent ? spec.parseParent(raw) : raw;
        return json(await store.list({ since, parentId }));
      }
      case "POST": {
        const item = spec.validate(await readJsonObject(req));
        return json(await store.upsert(item));
      }
      default:
        throw methodNotAllowed(method);
    }
  }

  if (path.length === 1 && path[0] === "batch" && method === "POST") {
    const items = validateBatch(await readJsonObject(req), (i) => spec.validate(i));
    return json({ results: await store.upsertMany(items) });
  }

  if (path.length !== 1) throw notFound(`Unknown route ${url.pathname}`);
  const rawId = path[0];
  if (!["GET", "PUT", "DELETE"].includes(method)) throw methodNotAllowed(method);
  const id = spec.parseId ? spec.parseId(rawId) : rawId;

  switch (method) {
    case "GET": {
      const item = await store.get(id);
      if (!item) throw notFound(`No ${spec.name} item with id ${id}`);
      return json(item);
    }
    case "PUT": {
      const item = spec.validate(await readJsonObject(req), rawId);
      return json(await store.upsert(item));
    }
    case "DELETE": {
      const at = parseUpdatedAtParam(url.searchParams.get("updatedAt"));
      const result = await store.softDelete(id, at);
      if (!result) throw notFound(`No ${spec.name} item with id ${id}`);
      return json(result);
    }
    default:
      throw methodNotAllowed(method);
  }
}
