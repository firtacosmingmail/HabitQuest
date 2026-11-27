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

export type GoalStatus = "notStarted" | "inProgress" | "done";

export interface Goal {
  id: string;
  projectId: string;
  title: string;
  deadline: string;
  status: GoalStatus;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

export interface PlanTask {
  id: string;
  goalId: string;
  title: string;
  deliveryDate: string | null;
  done: boolean;
  position: number;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

export type BlockRecurrence =
  | { type: "weekly"; weekdays: number[] }
  | { type: "monthly"; monthDays: number[] };

/** A recurring block of time of a project (open-ended when endDate is null). */
export interface TimeBlock {
  id: string;
  projectId: string;
  label: string | null;
  startTime: string;
  endTime: string;
  recurrence: BlockRecurrence;
  startDate: string | null;
  endDate: string | null;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

/** A text item of a goal (what to do consistently). */
export interface ConsistentAction {
  id: string;
  goalId: string;
  text: string;
  sortOrder: number;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

/**
 * Keyed by (timeBlockId, date). `id` = "<timeBlockId>|<yyyy-MM-dd>" is derived
 * (the app's sync queue key); it is added to responses and optional in requests.
 */
export interface SessionMark {
  id: string;
  timeBlockId: string;
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
