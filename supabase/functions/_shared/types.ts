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

// Projects (docs/PROJECTS.md) -------------------------------------------------

export interface Project {
  id: string;
  name: string;
  archived: boolean;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

export type TargetStatus = "notStarted" | "inProgress" | "done";

export interface Target {
  id: string;
  projectId: string;
  title: string;
  deadline: string;
  status: TargetStatus;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

export interface PlanTask {
  id: string;
  targetId: string;
  title: string;
  deliveryDate: string | null;
  done: boolean;
  position: number;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

export type ActionRecurrence =
  | { type: "weekly"; weekdays: number[] }
  | { type: "monthly"; monthDays: number[] };

export interface ConsistentAction {
  id: string;
  targetId: string;
  startTime: string;
  endTime: string;
  recurrence: ActionRecurrence;
  startDate: string | null;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

/**
 * Keyed by (actionId, date). `id` = "<actionId>|<yyyy-MM-dd>" is derived (the
 * app's sync queue key); it is added to responses and optional in requests.
 */
export interface SessionMark {
  id: string;
  actionId: string;
  date: string;
  attended: boolean;
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
