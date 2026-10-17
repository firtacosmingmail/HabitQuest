/**
 * `admin-stats`: read-only, aggregated usage statistics for the admin console
 * (see supabase/API.md).
 *
 * The database does the counting (public.admin_stats, migration
 * 20261017120000_admin_functions.sql) and returns sparse aggregates only:
 * counts per day/week and histograms of values, never a user id, email or
 * habit name. This module validates the request, runs the admin check, fills
 * the daily series with zeros, derives the weekly sums and groups the
 * histograms into fixed buckets. It is unit-tested with a fake [StatsStore]
 * (tests/admin_test.ts).
 */
import { type AdminCaller, requireAdmin } from "./admin.ts";
import { invalidInput, json, methodNotAllowed, notFound } from "./errors.ts";
import { subPath } from "./http.ts";
import { epochDay, fromEpochDay, utcToday } from "./quotes.ts";
import { parseDateParam } from "./validation.ts";

/** {d: day, n: count}; days without data are omitted. */
export interface DayCount {
  d: string;
  n: number;
}

/** {v: value, n: users}. */
export interface ValueCount {
  v: number;
  n: number;
}

/** What public.admin_stats returns (snake_case, sparse). */
export interface RawStats {
  totals: {
    users: number;
    players: number;
    habits: number;
    active_habits: number;
    completions: number;
    quotes: number;
    scheduled_quotes: number;
    quote_loves: number;
  };
  in_range: {
    signups: number;
    active_users: number;
    habits_created: number;
    completions: number;
    quote_loves: number;
  };
  signups: DayCount[];
  active: DayCount[];
  weekly_active: { w: string; n: number }[];
  habits_created: DayCount[];
  completions: DayCount[];
  loves: DayCount[];
  xp: ValueCount[];
  best_streak: ValueCount[];
  level: ValueCount[];
  top_quotes: {
    id: string;
    text: string;
    author: string | null;
    day: string | null;
    loves: number;
  }[];
}

export interface StatsStore {
  raw(from: string, to: string): Promise<RawStats>;
}

export interface AdminStatsDeps<C extends AdminCaller = AdminCaller> {
  authenticate(req: Request): Promise<C>;
  store(caller: C): StatsStore;
  admins(): string[];
  now?(): Date;
}

export const DEFAULT_STATS_DAYS = 30;
export const MAX_STATS_DAYS = 366;

/** A histogram bucket: min..max inclusive; max null = open-ended. */
export interface Bucket {
  label: string;
  min: number;
  max: number | null;
  users: number;
}

export const XP_BUCKETS: [number, number | null][] = [
  [0, 0],
  [1, 99],
  [100, 499],
  [500, 999],
  [1000, 2499],
  [2500, 4999],
  [5000, 9999],
  [10000, null],
];

export const STREAK_BUCKETS: [number, number | null][] = [
  [0, 0],
  [1, 2],
  [3, 6],
  [7, 13],
  [14, 29],
  [30, 59],
  [60, 99],
  [100, null],
];

const num = (v: unknown) => (typeof v === "number" ? v : Number(v ?? 0)) || 0;

function bucketLabel(min: number, max: number | null): string {
  if (max === null) return `${min}+`;
  if (min === max) return `${min}`;
  return `${min}–${max}`;
}

/** Groups a value histogram into [edges] (values below the first edge go to it). */
export function toBuckets(values: ValueCount[], edges: [number, number | null][]): Bucket[] {
  const out = edges.map(([min, max]) => ({ label: bucketLabel(min, max), min, max, users: 0 }));
  for (const { v, n } of values) {
    const value = num(v);
    let i = out.findIndex((b) => value >= b.min && (b.max === null || value <= b.max));
    if (i < 0) i = value < out[0].min ? 0 : out.length - 1;
    out[i].users += num(n);
  }
  return out;
}

/** Every day of [from, to] with its count (0 when absent). */
export function fillDays(series: DayCount[], from: string, to: string): number[] {
  const start = epochDay(from);
  const out = new Array(epochDay(to) - start + 1).fill(0);
  for (const { d, n } of series) {
    const i = epochDay(String(d).slice(0, 10)) - start;
    if (i >= 0 && i < out.length) out[i] += num(n);
  }
  return out;
}

/** The Monday (ISO week start) of [day]. */
export function weekStart(day: string): string {
  const n = epochDay(day);
  // 1970-01-01 was a Thursday: (n + 3) mod 7 = days since Monday.
  return fromEpochDay(n - (((n + 3) % 7) + 7) % 7);
}

/** Resolves ?from=&to= (default: the last 30 days up to today, UTC). */
export function statsRange(params: URLSearchParams, today: string): { from: string; to: string } {
  const to = parseDateParam(params.get("to"), "to") ?? today;
  const from = parseDateParam(params.get("from"), "from") ??
    fromEpochDay(epochDay(to) - (DEFAULT_STATS_DAYS - 1));
  if (from > to) throw invalidInput("from must not be after to");
  if (epochDay(to) - epochDay(from) + 1 > MAX_STATS_DAYS) {
    throw invalidInput(`The range must span at most ${MAX_STATS_DAYS} days`);
  }
  return { from, to };
}

/** Builds the admin-stats response from the database aggregates. */
export function buildStats(raw: RawStats, from: string, to: string, now: Date) {
  const days = epochDay(to) - epochDay(from) + 1;
  const series = {
    signups: fillDays(raw.signups ?? [], from, to),
    activeUsers: fillDays(raw.active ?? [], from, to),
    habitsCreated: fillDays(raw.habits_created ?? [], from, to),
    completions: fillDays(raw.completions ?? [], from, to),
    quoteLoves: fillDays(raw.loves ?? [], from, to),
  };
  const daily = Array.from({ length: days }, (_, i) => ({
    date: fromEpochDay(epochDay(from) + i),
    signups: series.signups[i],
    activeUsers: series.activeUsers[i],
    habitsCreated: series.habitsCreated[i],
    completions: series.completions[i],
    quoteLoves: series.quoteLoves[i],
  }));

  const weeklyActive = new Map(
    (raw.weekly_active ?? []).map((w) => [String(w.w).slice(0, 10), num(w.n)]),
  );
  const weeks = new Map<string, { signups: number; completions: number; days: number }>();
  for (const d of daily) {
    const w = weekStart(d.date);
    const cur = weeks.get(w) ?? { signups: 0, completions: 0, days: 0 };
    cur.signups += d.signups;
    cur.completions += d.completions;
    cur.days += 1;
    weeks.set(w, cur);
  }
  const weekly = [...weeks.entries()].map(([w, v]) => ({
    weekStart: w,
    /** Days of this week inside the range (< 7 for a partial edge week). */
    days: v.days,
    signups: v.signups,
    completions: v.completions,
    activeUsers: weeklyActive.get(w) ?? 0,
  }));

  const sum = (xs: number[]) => xs.reduce((a, b) => a + b, 0);
  const t = raw.totals;
  const r = raw.in_range;
  return {
    from,
    to,
    days,
    generatedAt: now.toISOString(),
    totals: {
      users: num(t?.users),
      usersWithGameState: num(t?.players),
      habits: num(t?.habits),
      activeHabits: num(t?.active_habits),
      completions: num(t?.completions),
      quotes: num(t?.quotes),
      scheduledQuotes: num(t?.scheduled_quotes),
      quoteLoves: num(t?.quote_loves),
    },
    range: {
      signups: num(r?.signups),
      activeUsers: num(r?.active_users),
      habitsCreated: num(r?.habits_created),
      completions: num(r?.completions),
      quoteLoves: num(r?.quote_loves),
      averageDailyActiveUsers: Math.round((sum(series.activeUsers) / days) * 10) / 10,
    },
    daily,
    weekly,
    xpBuckets: toBuckets(raw.xp ?? [], XP_BUCKETS),
    bestStreakBuckets: toBuckets(raw.best_streak ?? [], STREAK_BUCKETS),
    levels: (raw.level ?? []).map((l) => ({ level: num(l.v), users: num(l.n) })),
    topQuotes: (raw.top_quotes ?? []).map((q) => ({
      id: q.id,
      text: q.text,
      author: q.author ?? null,
      day: q.day ?? null,
      loves: num(q.loves),
    })),
    widgets: {
      recorded: false,
      note: "Widget usage is not recorded: no table or event stores widget views or taps.",
    },
  };
}

export type AdminStats = ReturnType<typeof buildStats>;

export async function handleAdminStats<C extends AdminCaller>(
  req: Request,
  deps: AdminStatsDeps<C>,
): Promise<Response> {
  const url = new URL(req.url);
  const path = subPath(url, "admin-stats");
  if (path.length > 1 || (path.length === 1 && path[0] !== "me")) {
    throw notFound(`Unknown route ${url.pathname}`);
  }
  const method = req.method.toUpperCase();
  if (method !== "GET") throw methodNotAllowed(method);

  const caller = await deps.authenticate(req);
  requireAdmin(caller, deps.admins(), "Only admins can read the stats");

  // GET /admin-stats/me: the console's sign-in gate.
  if (path.length === 1) {
    return json({ admin: true, email: caller.email, serviceRole: caller.serviceRole });
  }

  const now = deps.now?.() ?? new Date();
  const { from, to } = statsRange(url.searchParams, utcToday(now));
  const raw = await deps.store(caller).raw(from, to);
  return json(buildStats(raw, from, to, now));
}
