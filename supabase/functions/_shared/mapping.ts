/** JSON (camelCase, contract) ↔ database row (snake_case) mapping. */
import { toIsoMillis } from "./validation.ts";
import type { CheckIn, GameState, Habit, JsonObject, Session } from "./types.ts";

export interface HabitRow {
  user_id?: string;
  id: string;
  name: string;
  emoji: string;
  color: number;
  schedule: JsonObject;
  reminder_time: string | null;
  created_at: string;
  archived: boolean;
  updated_at: string;
  deleted_at: string | null;
  server_updated_at?: string;
}

export interface CheckInRow {
  user_id?: string;
  id: string;
  habit_id: string;
  date: string;
  completed: boolean;
  updated_at: string;
  deleted_at: string | null;
  server_updated_at?: string;
}

export interface GameStateRow {
  user_id?: string;
  state: JsonObject;
  updated_at: string;
  server_updated_at?: string;
}

const tsOrNull = (v: string | null | undefined) =>
  v === null || v === undefined ? null : toIsoMillis(v);

export function habitToRow(h: Habit): HabitRow {
  return {
    id: h.id,
    name: h.name,
    emoji: h.emoji,
    color: h.color,
    schedule: h.schedule,
    reminder_time: h.reminderTime,
    created_at: h.createdAt,
    archived: h.archived,
    updated_at: h.updatedAt,
    deleted_at: h.deletedAt,
  };
}

export function rowToHabit(r: HabitRow): Habit {
  return {
    id: r.id,
    name: r.name,
    emoji: r.emoji,
    color: Number(r.color),
    schedule: r.schedule,
    reminderTime: r.reminder_time,
    createdAt: toIsoMillis(r.created_at),
    archived: r.archived,
    updatedAt: toIsoMillis(r.updated_at),
    deletedAt: tsOrNull(r.deleted_at),
  };
}

export function checkInToRow(c: CheckIn): CheckInRow {
  return {
    id: c.id,
    habit_id: c.habitId,
    date: c.date,
    completed: c.completed,
    updated_at: c.updatedAt,
    deleted_at: c.deletedAt,
  };
}

export function rowToCheckIn(r: CheckInRow): CheckIn {
  return {
    id: r.id,
    habitId: r.habit_id,
    date: r.date.slice(0, 10),
    completed: r.completed,
    updatedAt: toIsoMillis(r.updated_at),
    deletedAt: tsOrNull(r.deleted_at),
  };
}

export function rowToGameState(r: GameStateRow): GameState {
  return { state: r.state, updatedAt: toIsoMillis(r.updated_at) };
}

/** Session as returned by supabase-js (subset). */
export interface AuthSessionLike {
  access_token: string;
  refresh_token: string;
  expires_at?: number;
  expires_in?: number;
  user: { id: string; email?: string | null };
}

/** Maps a Supabase Auth session to the contract Session. */
export function toSession(
  s: AuthSessionLike,
  nowSeconds = Math.floor(Date.now() / 1000),
): Session {
  const expiresAt = typeof s.expires_at === "number"
    ? Math.floor(s.expires_at)
    : nowSeconds + Math.floor(s.expires_in ?? 3600);
  return {
    accessToken: s.access_token,
    refreshToken: s.refresh_token,
    expiresAt,
    user: { id: s.user.id, email: s.user.email ?? null },
  };
}
