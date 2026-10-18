/** In-memory stores mirroring the SQL LWW semantics, for handler tests. */
import { shouldApply, tombstone } from "../_shared/lww.ts";
import type { ListQuery, ResourceStore } from "../_shared/resource.ts";
import type { GameStateStore } from "../_shared/game_state.ts";
import type { BatchResult, GameState, WriteResult } from "../_shared/types.ts";
import { ApiError } from "../_shared/errors.ts";
import {
  dayTaken,
  type LovedQuote,
  type LoveStore,
  type Quote,
  type QuoteStore,
} from "../_shared/quotes.ts";
import type { AdminQuoteStore } from "../_shared/admin_quotes.ts";

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

// Quotes -----------------------------------------------------------------------

/** In-memory `quotes` + `quote_loves`, mirroring the SQL semantics. */
export class MemoryQuotes {
  readonly quotes = new Map<string, Quote>();
  /** userId → quoteId → lovedAt */
  readonly loves = new Map<string, Map<string, string>>();
  clock = Date.UTC(2026, 9, 16, 12, 0, 0);
  private seq = 0;

  private tick(): string {
    this.clock += 1000;
    return new Date(this.clock).toISOString();
  }

  /** Adds a quote with a deterministic uuid (ids sort like the insert order). */
  add(text: string, day: string | null, author: string | null = null): Quote {
    const id = `00000000-0000-4000-8000-${(++this.seq).toString(16).padStart(12, "0")}`;
    const at = this.tick();
    const q: Quote = { id, text, author, day, createdAt: at, updatedAt: at };
    this.quotes.set(id, q);
    return q;
  }

  private sorted(before: string | null): Quote[] {
    return [...this.quotes.values()]
      .filter((q) => before === null || (q.day !== null && q.day < before))
      .sort((a, b) => {
        if (a.day !== b.day) {
          if (a.day === null) return 1;
          if (b.day === null) return -1;
          return a.day < b.day ? -1 : 1;
        }
        return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
      });
  }

  private checkDay(day: string | null | undefined, self?: string) {
    if (!day) return;
    for (const q of this.quotes.values()) {
      if (q.day === day && q.id !== self) throw dayTaken(day);
    }
  }

  store(userId: string | null): QuoteStore {
    return {
      byDay: (day) => Promise.resolve([...this.quotes.values()].find((q) => q.day === day) ?? null),
      count: (before) => Promise.resolve(this.sorted(before).length),
      nth: (before, i) => Promise.resolve(this.sorted(before)[i] ?? null),
      range: (from, to) =>
        Promise.resolve(
          this.sorted(null).filter((q) => q.day !== null && q.day >= from && q.day <= to)
            .reverse(),
        ),
      create: (input) => {
        this.checkDay(input.day);
        const q = this.add(input.text, input.day, input.author);
        return Promise.resolve(q);
      },
      update: (id, patch) => {
        const q = this.quotes.get(id);
        if (!q) return Promise.resolve(null);
        this.checkDay(patch.day, id);
        const next = { ...q, ...patch, updatedAt: this.tick() };
        this.quotes.set(id, next);
        return Promise.resolve(next);
      },
      lovedIds: (ids) => {
        const mine = userId === null ? new Map() : this.loves.get(userId) ?? new Map();
        return Promise.resolve(new Set(ids.filter((id) => mine.has(id))));
      },
    };
  }

  /** The admin view (admin-quotes), mirroring public.admin_list_quotes. */
  adminStore(): AdminQuoteStore {
    const loveCount = (id: string) => [...this.loves.values()].filter((m) => m.has(id)).length;
    return {
      search: (s) => {
        const needle = s.query?.toLowerCase() ?? null;
        const hits = [...this.quotes.values()].filter((q) =>
          (needle === null || q.text.toLowerCase().includes(needle) ||
            (q.author ?? "").toLowerCase().includes(needle)) &&
          (s.from === null || (q.day !== null && q.day >= s.from)) &&
          (s.to === null || (q.day !== null && q.day <= s.to)) &&
          (s.scheduled !== "scheduled" || q.day !== null) &&
          (s.scheduled !== "unscheduled" || q.day === null)
        ).sort((a, b) => {
          if (a.day !== b.day) {
            if (a.day === null) return -1;
            if (b.day === null) return 1;
            return a.day < b.day ? 1 : -1;
          }
          if (a.createdAt !== b.createdAt) return a.createdAt < b.createdAt ? 1 : -1;
          return a.id < b.id ? -1 : 1;
        });
        return Promise.resolve({
          total: hits.length,
          items: hits.slice(s.offset, s.offset + s.limit)
            .map((q) => ({ ...q, loves: loveCount(q.id) })),
        });
      },
      delete: (id) => {
        const existed = this.quotes.delete(id);
        for (const m of this.loves.values()) m.delete(id); // on delete cascade
        return Promise.resolve(existed);
      },
    };
  }

  loveStore(userId: string): LoveStore {
    const mine = () => {
      if (!this.loves.has(userId)) this.loves.set(userId, new Map());
      return this.loves.get(userId)!;
    };
    const loved = (quoteId: string): LovedQuote => ({
      quote: this.quotes.get(quoteId)!,
      lovedAt: mine().get(quoteId)!,
    });
    return {
      list: () =>
        Promise.resolve(
          [...mine().keys()].map(loved)
            .sort((a, b) => a.lovedAt < b.lovedAt ? 1 : a.lovedAt > b.lovedAt ? -1 : 0),
        ),
      love: (quoteId) => {
        if (!this.quotes.has(quoteId)) return Promise.resolve(null);
        if (!mine().has(quoteId)) mine().set(quoteId, this.tick());
        return Promise.resolve(loved(quoteId));
      },
      unlove: (quoteId) => {
        mine().delete(quoteId);
        return Promise.resolve();
      },
    };
  }
}
