/**
 * Generic HTTP handler for the LWW resources (`habits`, `check-ins`). The
 * storage is behind [ResourceStore] so the routing and validation can be
 * tested without a database (see tests/resource_test.ts).
 */
import { json, methodNotAllowed, notFound } from "./errors.ts";
import { readJsonObject, subPath } from "./http.ts";
import {
  parseSince,
  parseUpdatedAtParam,
  validateBatch,
  validateCheckIn,
  validateHabit,
} from "./validation.ts";
import type { BatchResult, CheckIn, Habit, WriteResult } from "./types.ts";

export interface ListQuery {
  since: string | null;
  habitId: string | null;
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
  /** Whether the list supports `?habitId=`. */
  habitIdFilter: boolean;
}

export const habitsSpec: ResourceSpec<Habit> = {
  name: "habits",
  validate: validateHabit,
  habitIdFilter: false,
};

export const checkInsSpec: ResourceSpec<CheckIn> = {
  name: "check-ins",
  validate: validateCheckIn,
  habitIdFilter: true,
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
        const habitId = spec.habitIdFilter ? (url.searchParams.get("habitId") || null) : null;
        return json(await store.list({ since, habitId }));
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
  const id = path[0];

  switch (method) {
    case "GET": {
      const item = await store.get(id);
      if (!item) throw notFound(`No ${spec.name} item with id ${id}`);
      return json(item);
    }
    case "PUT": {
      const item = spec.validate(await readJsonObject(req), id);
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
