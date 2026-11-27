/** Projects: JSON (camelCase, contract) ↔ database row (snake_case) mapping. */
import { sessionMarkId } from "./projects_validation.ts";
import type {
  BlockRecurrence,
  ConsistentAction,
  Goal,
  GoalStatus,
  PlanTask,
  Project,
  SessionMark,
  TimeBlock,
} from "./types.ts";
import { toIsoMillis } from "./validation.ts";

interface Server {
  user_id?: string;
  server_updated_at?: string;
}

export interface ProjectRow extends Server {
  id: string;
  name: string;
  archived: boolean;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface GoalRow extends Server {
  id: string;
  project_id: string;
  title: string;
  deadline: string;
  status: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface PlanTaskRow extends Server {
  id: string;
  goal_id: string;
  title: string;
  delivery_date: string | null;
  done: boolean;
  position: number;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface TimeBlockRow extends Server {
  id: string;
  project_id: string;
  label: string | null;
  start_time: string;
  end_time: string;
  recurrence: BlockRecurrence;
  start_date: string | null;
  end_date: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface ConsistentActionRow extends Server {
  id: string;
  goal_id: string;
  text: string;
  sort_order: number;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface SessionMarkRow extends Server {
  time_block_id: string;
  date: string;
  attended: boolean;
  updated_at: string;
  deleted_at: string | null;
}

const tsOrNull = (v: string | null | undefined) =>
  v === null || v === undefined ? null : toIsoMillis(v);
const day = (v: string) => v.slice(0, 10);
const dayOrNull = (v: string | null | undefined) => v === null || v === undefined ? null : day(v);

export function projectToRow(p: Project): ProjectRow {
  return {
    id: p.id,
    name: p.name,
    archived: p.archived,
    created_at: p.createdAt,
    updated_at: p.updatedAt,
    deleted_at: p.deletedAt,
  };
}

export function rowToProject(r: ProjectRow): Project {
  return {
    id: r.id,
    name: r.name,
    archived: r.archived,
    createdAt: toIsoMillis(r.created_at),
    updatedAt: toIsoMillis(r.updated_at),
    deletedAt: tsOrNull(r.deleted_at),
  };
}

export function goalToRow(g: Goal): GoalRow {
  return {
    id: g.id,
    project_id: g.projectId,
    title: g.title,
    deadline: g.deadline,
    status: g.status,
    created_at: g.createdAt,
    updated_at: g.updatedAt,
    deleted_at: g.deletedAt,
  };
}

export function rowToGoal(r: GoalRow): Goal {
  return {
    id: r.id,
    projectId: r.project_id,
    title: r.title,
    deadline: day(r.deadline),
    status: r.status as GoalStatus,
    createdAt: toIsoMillis(r.created_at),
    updatedAt: toIsoMillis(r.updated_at),
    deletedAt: tsOrNull(r.deleted_at),
  };
}

export function planTaskToRow(k: PlanTask): PlanTaskRow {
  return {
    id: k.id,
    goal_id: k.goalId,
    title: k.title,
    delivery_date: k.deliveryDate,
    done: k.done,
    position: k.position,
    created_at: k.createdAt,
    updated_at: k.updatedAt,
    deleted_at: k.deletedAt,
  };
}

export function rowToPlanTask(r: PlanTaskRow): PlanTask {
  return {
    id: r.id,
    goalId: r.goal_id,
    title: r.title,
    deliveryDate: dayOrNull(r.delivery_date),
    done: r.done,
    position: Number(r.position),
    createdAt: toIsoMillis(r.created_at),
    updatedAt: toIsoMillis(r.updated_at),
    deletedAt: tsOrNull(r.deleted_at),
  };
}

export function timeBlockToRow(b: TimeBlock): TimeBlockRow {
  return {
    id: b.id,
    project_id: b.projectId,
    label: b.label,
    start_time: b.startTime,
    end_time: b.endTime,
    recurrence: b.recurrence,
    start_date: b.startDate,
    end_date: b.endDate,
    created_at: b.createdAt,
    updated_at: b.updatedAt,
    deleted_at: b.deletedAt,
  };
}

export function rowToTimeBlock(r: TimeBlockRow): TimeBlock {
  return {
    id: r.id,
    projectId: r.project_id,
    label: r.label ?? null,
    startTime: r.start_time,
    endTime: r.end_time,
    recurrence: r.recurrence,
    startDate: dayOrNull(r.start_date),
    endDate: dayOrNull(r.end_date),
    createdAt: toIsoMillis(r.created_at),
    updatedAt: toIsoMillis(r.updated_at),
    deletedAt: tsOrNull(r.deleted_at),
  };
}

export function consistentActionToRow(a: ConsistentAction): ConsistentActionRow {
  return {
    id: a.id,
    goal_id: a.goalId,
    text: a.text,
    sort_order: a.sortOrder,
    created_at: a.createdAt,
    updated_at: a.updatedAt,
    deleted_at: a.deletedAt,
  };
}

export function rowToConsistentAction(r: ConsistentActionRow): ConsistentAction {
  return {
    id: r.id,
    goalId: r.goal_id,
    text: r.text,
    sortOrder: Number(r.sort_order),
    createdAt: toIsoMillis(r.created_at),
    updatedAt: toIsoMillis(r.updated_at),
    deletedAt: tsOrNull(r.deleted_at),
  };
}

export function sessionMarkToRow(m: SessionMark): SessionMarkRow {
  return {
    time_block_id: m.timeBlockId,
    date: m.date,
    attended: m.attended,
    updated_at: m.updatedAt,
    deleted_at: m.deletedAt,
  };
}

export function rowToSessionMark(r: SessionMarkRow): SessionMark {
  const date = day(r.date);
  return {
    id: sessionMarkId(r.time_block_id, date),
    timeBlockId: r.time_block_id,
    date,
    attended: r.attended,
    updatedAt: toIsoMillis(r.updated_at),
    deletedAt: tsOrNull(r.deleted_at),
  };
}
