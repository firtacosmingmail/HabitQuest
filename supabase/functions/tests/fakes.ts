/** In-memory stores mirroring the SQL LWW semantics, for handler tests. */
import { shouldApply, tombstone } from "../_shared/lww.ts";
import type { ListQuery, ResourceStore } from "../_shared/resource.ts";
import type { GameStateStore } from "../_shared/game_state.ts";
import type { BatchResult, GameState, WriteResult } from "../_shared/types.ts";
import { ApiError } from "../_shared/errors.ts";

interface Entry<T> {
  item: T;
  serverUpdatedAt: number;
}

type Syncable = { id: string; updatedAt: string; deletedAt: string | null };

export class MemoryStore<T extends Syncable> implements ResourceStore<T> {
  readonly rows = new Map<string, Entry<T>>();
  /** Fake database clock (ms), advanced on every write. */
  clock = Date.UTC(2026, 9, 7, 12, 0, 0);
  /** Optional referential check (e.g. check-in → habit). */
  constructor(private readonly check?: (item: T) => void) {}

  private write(item: T) {
    this.clock += 1000;
    this.rows.set(item.id, { item, serverUpdatedAt: this.clock });
  }

  list(q: ListQuery) {
    const since = q.since ? Date.parse(q.since) : null;
    const items = [...this.rows.values()]
      .filter((e) => since === null || e.serverUpdatedAt > since)
      .filter((e) =>
        q.habitId === null || (e.item as unknown as { habitId?: string }).habitId === q.habitId
      )
      .sort((a, b) => a.serverUpdatedAt - b.serverUpdatedAt)
      .map((e) => e.item);
    return Promise.resolve({
      items,
      serverTime: new Date(this.clock - 5000).toISOString(),
    });
  }

  get(id: string) {
    return Promise.resolve(this.rows.get(id)?.item ?? null);
  }

  upsertSync(item: T): WriteResult<T> {
    this.check?.(item);
    const stored = this.rows.get(item.id)?.item;
    if (shouldApply(item.updatedAt, stored)) {
      this.write(item);
      return { item, applied: true };
    }
    return { item: stored!, applied: false };
  }

  upsert(item: T) {
    return Promise.resolve(this.upsertSync(item));
  }

  upsertMany(items: T[]): Promise<BatchResult<T>[]> {
    // All-or-nothing like the SQL transaction.
    items.forEach((i) => this.check?.(i));
    return Promise.resolve(items.map((i) => ({ id: i.id, ...this.upsertSync(i) })));
  }

  softDelete(id: string, updatedAt: string | null) {
    const stored = this.rows.get(id)?.item;
    if (!stored) return Promise.resolve(null);
    const at = updatedAt ?? new Date(this.clock).toISOString();
    if (shouldApply(at, stored)) {
      const t = tombstone(stored, at);
      this.write(t);
      return Promise.resolve({ item: t, applied: true });
    }
    return Promise.resolve({ item: stored, applied: false });
  }
}

export class MemoryGameStateStore implements GameStateStore {
  value: GameState | null = null;
  get() {
    return Promise.resolve(this.value);
  }
  upsert(gs: GameState) {
    if (shouldApply(gs.updatedAt, this.value)) {
      this.value = gs;
      return Promise.resolve({ item: gs, applied: true });
    }
    return Promise.resolve({ item: this.value!, applied: false });
  }
  reset() {
    this.value = null;
    return Promise.resolve();
  }
}

export function habitMustExist<H extends Syncable>(habits: MemoryStore<H>) {
  return (item: { habitId: string }) => {
    if (!habits.rows.has(item.habitId)) {
      throw new ApiError(409, "habit_not_found", "habit missing");
    }
  };
}

export const base = "http://localhost/functions/v1";

export function req(
  method: string,
  path: string,
  body?: unknown,
  headers: Record<string, string> = {},
): Request {
  return new Request(`${base}/${path}`, {
    method,
    headers: { "content-type": "application/json", ...headers },
    body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body),
  });
}

export const habitBody = (over: Record<string, unknown> = {}) => ({
  id: "h1",
  name: "Drink water",
  emoji: "💧",
  color: 0xff2196f3,
  schedule: { type: "daily" },
  reminderTime: "08:30",
  createdAt: "2026-10-01T08:00:00.000Z",
  archived: false,
  updatedAt: "2026-10-07T09:15:00.000Z",
  deletedAt: null,
  ...over,
});

export const checkInBody = (over: Record<string, unknown> = {}) => ({
  id: "h1_2026-10-07",
  habitId: "h1",
  date: "2026-10-07",
  completed: true,
  updatedAt: "2026-10-07T09:15:00.000Z",
  deletedAt: null,
  ...over,
});
