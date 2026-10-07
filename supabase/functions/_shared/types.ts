/** JSON shapes of the API contract (supabase/API.md). */

export type JsonObject = Record<string, unknown>;

export interface Habit {
  id: string;
  name: string;
  emoji: string;
  color: number;
  schedule: JsonObject;
  reminderTime: string | null;
  createdAt: string;
  archived: boolean;
  updatedAt: string;
  deletedAt: string | null;
}

export interface CheckIn {
  id: string;
  habitId: string;
  date: string;
  completed: boolean;
  updatedAt: string;
  deletedAt: string | null;
}

export interface GameState {
  state: JsonObject;
  updatedAt: string;
}

export interface Session {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
  user: { id: string; email: string | null };
}

/** Result of a last-write-wins write. */
export interface WriteResult<T> {
  item: T;
  applied: boolean;
}

export interface BatchResult<T> extends WriteResult<T> {
  id: string;
}
