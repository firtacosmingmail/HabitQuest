/**
 * Daily quotes: the `quotes` and `quote-loves` endpoints (see supabase/API.md).
 *
 * Storage sits behind [QuoteStore] / [LoveStore] so routing, validation, the
 * deterministic fallback and the admin check are unit-tested with in-memory
 * fakes (tests/quotes_test.ts); supabase_quotes.ts holds the real stores.
 */
import {
  ApiError,
  forbidden,
  invalidInput,
  json,
  methodNotAllowed,
  noContent,
  notFound,
} from "./errors.ts";
import { readJsonObject, subPath } from "./http.ts";
import { type AdminCaller, requireAdmin } from "./admin.ts";
import {
  parseDateParam,
  type QuoteInput,
  type QuotePatch,
  requireUuid,
  validateQuoteInput,
  validateQuotePatch,
} from "./validation.ts";

/** A stored quote, as returned by the stores. */
export interface Quote {
  id: string;
  text: string;
  author: string | null;
  /** The UTC calendar day it is scheduled for, or null. */
  day: string | null;
  createdAt: string;
  updatedAt: string;
}

/** A quote in an API response: plus whether the caller loves it. */
export interface QuoteDto extends Quote {
  loved: boolean;
}

export interface LovedQuote {
  quote: Quote;
  lovedAt: string;
}

/**
 * Read/write access to `quotes`. `before` = null means "all quotes"; with a
 * date it means quotes whose day is strictly earlier. Ordering for count/nth
 * is (day asc, id asc), unscheduled (null-day) quotes last.
 */
export interface QuoteStore {
  byDay(day: string): Promise<Quote | null>;
  count(before: string | null): Promise<number>;
  nth(before: string | null, index: number): Promise<Quote | null>;
  /** Scheduled quotes with from <= day <= to, newest day first. */
  range(from: string, to: string): Promise<Quote[]>;
  /** Throws 409 day_taken when another quote is scheduled on that day. */
  create(input: QuoteInput): Promise<Quote>;
  /** Null when the id does not exist. Throws 409 day_taken like create. */
  update(id: string, patch: QuotePatch): Promise<Quote | null>;
  /** Which of [ids] the caller loves (empty for the service role). */
  lovedIds(ids: string[]): Promise<Set<string>>;
}

/** The signed-in caller's loves (RLS: own rows only). */
export interface LoveStore {
  /** Newest love first. */
  list(): Promise<LovedQuote[]>;
  /** Idempotent; keeps the first lovedAt. Null when the quote does not exist. */
  love(quoteId: string): Promise<LovedQuote | null>;
  /** Idempotent. */
  unlove(quoteId: string): Promise<void>;
}

export type QuoteCaller = AdminCaller;

export interface QuotesDeps<C extends QuoteCaller = QuoteCaller> {
  authenticate(req: Request): Promise<C>;
  store(caller: C): QuoteStore;
  /** Lower-cased admin emails (QUOTE_ADMINS). */
  admins(): string[];
  now?(): Date;
}

export interface LovesDeps<C extends QuoteCaller = QuoteCaller> {
  authenticate(req: Request): Promise<C>;
  store(caller: C): LoveStore;
}

export const MAX_HISTORY_DAYS = 366;
export const DAY_MS = 86_400_000;

export const dayTaken = (day: string) =>
  new ApiError(409, "day_taken", `Another quote is already scheduled on ${day}`);

// Dates ------------------------------------------------------------------------

/** Days since 1970-01-01 of a `yyyy-MM-dd` date (negative before 1970). */
export function epochDay(date: string): number {
  const [y, m, d] = date.split("-").map(Number);
  return Math.floor(Date.UTC(y, m - 1, d) / DAY_MS);
}

/** The `yyyy-MM-dd` date of an epoch day. */
export function fromEpochDay(n: number): string {
  return new Date(n * DAY_MS).toISOString().slice(0, 10);
}

export function utcToday(now: Date): string {
  return now.toISOString().slice(0, 10);
}

/** Fallback index for [date] among [count] candidates (always 0..count-1). */
export function fallbackIndex(date: string, count: number): number {
  return ((epochDay(date) % count) + count) % count;
}

// The admin check lives in admin.ts (shared with admin-quotes / admin-stats);
// re-exported here for existing callers.
export { isAdmin, parseAdmins } from "./admin.ts";

// Quote of the day -------------------------------------------------------------

export interface DailyQuote {
  date: string;
  fallback: boolean;
  quote: Quote;
}

/**
 * The quote of [date]: the one scheduled that day, else a deterministic pick
 * among the quotes scheduled before it (all quotes if none are older),
 * ordered by (day, id), at index epochDay(date) mod count. Null when the
 * table is empty.
 */
export async function quoteForDate(store: QuoteStore, date: string): Promise<DailyQuote | null> {
  const scheduled = await store.byDay(date);
  if (scheduled) return { date, fallback: false, quote: scheduled };
  let before: string | null = date;
  let count = await store.count(before);
  if (count === 0) {
    before = null;
    count = await store.count(null);
  }
  if (count === 0) return null;
  const quote = await store.nth(before, fallbackIndex(date, count));
  return quote ? { date, fallback: true, quote } : null;
}

// Handlers ---------------------------------------------------------------------

async function withLoved(store: QuoteStore, quotes: Quote[]): Promise<QuoteDto[]> {
  const loved = quotes.length > 0 ? await store.lovedIds(quotes.map((q) => q.id)) : new Set();
  return quotes.map((q) => ({ ...q, loved: loved.has(q.id) }));
}

/** Resolves the history range: ?from=&to= or ?past=N, capped at today (UTC). */
export function historyRange(params: URLSearchParams, today: string): { from: string; to: string } {
  const past = params.get("past");
  const fromRaw = params.get("from");
  const toRaw = params.get("to");
  const todayN = epochDay(today);
  if (past !== null) {
    if (fromRaw !== null || toRaw !== null) {
      throw invalidInput("Use either past or from/to, not both");
    }
    if (!/^\d+$/.test(past) || Number(past) < 1 || Number(past) > MAX_HISTORY_DAYS) {
      throw invalidInput(`past must be an integer from 1 to ${MAX_HISTORY_DAYS}`);
    }
    return { from: fromEpochDay(todayN - Number(past)), to: fromEpochDay(todayN - 1) };
  }
  const from = parseDateParam(fromRaw, "from");
  const toParam = parseDateParam(toRaw, "to");
  if (from === null || toParam === null) throw invalidInput("from and to are both required");
  if (from > toParam) throw invalidInput("from must not be after to");
  if (epochDay(toParam) - epochDay(from) + 1 > MAX_HISTORY_DAYS) {
    throw invalidInput(`The range must span at most ${MAX_HISTORY_DAYS} days`);
  }
  const to = toParam > today ? today : toParam;
  return { from, to };
}

export async function handleQuotes<C extends QuoteCaller>(
  req: Request,
  deps: QuotesDeps<C>,
): Promise<Response> {
  const url = new URL(req.url);
  if (subPath(url, "quotes").length !== 0) throw notFound(`Unknown route ${url.pathname}`);
  const method = req.method.toUpperCase();
  if (!["GET", "POST", "PUT"].includes(method)) throw methodNotAllowed(method);

  const caller = await deps.authenticate(req);
  const store = deps.store(caller);
  const params = url.searchParams;
  const today = utcToday(deps.now?.() ?? new Date());

  if (method === "GET") {
    const isHistory = params.has("from") || params.has("to") || params.has("past");
    if (isHistory) {
      if (params.has("date")) throw invalidInput("Use either date or a history range, not both");
      const { from, to } = historyRange(params, today);
      const items = from <= to ? await store.range(from, to) : [];
      return json({ from, to, items: await withLoved(store, items) });
    }
    const date = parseDateParam(params.get("date"), "date") ?? today;
    const daily = await quoteForDate(store, date);
    if (!daily) throw notFound("There are no quotes yet");
    const [quote] = await withLoved(store, [daily.quote]);
    return json({ date, fallback: daily.fallback, quote });
  }

  requireAdmin(caller, deps.admins(), "Only quote admins can change quotes");

  if (method === "POST") {
    const input = validateQuoteInput(await readJsonObject(req));
    const created = await store.create(input);
    const [quote] = await withLoved(store, [created]);
    return json({ quote }, 201);
  }

  // PUT ?id=
  const id = requireUuid(params.get("id"), "id");
  const patch = validateQuotePatch(await readJsonObject(req));
  const updated = await store.update(id, patch);
  if (!updated) throw notFound(`No quote with id ${id}`);
  const [quote] = await withLoved(store, [updated]);
  return json({ quote });
}

const lovedDto = (l: LovedQuote) => ({ ...l.quote, loved: true, lovedAt: l.lovedAt });

export async function handleQuoteLoves<C extends QuoteCaller>(
  req: Request,
  deps: LovesDeps<C>,
): Promise<Response> {
  const url = new URL(req.url);
  if (subPath(url, "quote-loves").length !== 0) throw notFound(`Unknown route ${url.pathname}`);
  const method = req.method.toUpperCase();
  if (!["GET", "POST", "DELETE"].includes(method)) throw methodNotAllowed(method);

  const caller = await deps.authenticate(req);
  if (caller.userId === null) throw forbidden("Loves belong to a signed-in user");
  const store = deps.store(caller);

  switch (method) {
    case "GET":
      return json({ items: (await store.list()).map(lovedDto) });
    case "POST": {
      const body = await readJsonObject(req);
      const quoteId = requireUuid(body.quoteId, "quoteId");
      const loved = await store.love(quoteId);
      if (!loved) throw notFound(`No quote with id ${quoteId}`);
      return json(lovedDto(loved));
    }
    default: {
      const quoteId = requireUuid(url.searchParams.get("quoteId"), "quoteId");
      await store.unlove(quoteId);
      return noContent();
    }
  }
}
