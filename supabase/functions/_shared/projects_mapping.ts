/** Projects: JSON (camelCase, contract) ↔ database row (snake_case) mapping. */
import { sessionMarkId } from "./projects_validation.ts";
import type {
  ActionRecurrence,
  ConsistentAction,
  PlanTask,
  Project,
  SessionMark,
  Target,
  TargetStatus,
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

export interface TargetRow extends Server {
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
  target_id: string;
  title: string;
  delivery_date: string | null;
  done: boolean;
  position: number;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface ConsistentActionRow extends Server {
  id: string;
  target_id: string;
  start_time: string;
  end_time: string;
  recurrence: ActionRecurrence;
  start_date: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface SessionMarkRow extends Server {
  action_id: string;
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

export function targetToRow(t: Target): TargetRow {
  return {
    id: t.id,
    project_id: t.projectId,
    title: t.title,
    deadline: t.deadline,
    status: t.status,
    created_at: t.createdAt,
    updated_at: t.updatedAt,
    deleted_at: t.deletedAt,
  };
}

export function rowToTarget(r: TargetRow): Target {
  return {
    id: r.id,
    projectId: r.project_id,
    title: r.title,
    deadline: day(r.deadline),
    status: r.status as TargetStatus,
    createdAt: toIsoMillis(r.created_at),
    updatedAt: toIsoMillis(r.updated_at),
    deletedAt: tsOrNull(r.deleted_at),
  };
}

export function planTaskToRow(k: PlanTask): PlanTaskRow {
  return {
    id: k.id,
    target_id: k.targetId,
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
    targetId: r.target_id,
    title: r.title,
    deliveryDate: dayOrNull(r.delivery_date),
    done: r.done,
    position: Number(r.position),
    createdAt: toIsoMillis(r.created_at),
    updatedAt: toIsoMillis(r.updated_at),
    deletedAt: tsOrNull(r.deleted_at),
  };
}

export function consistentActionToRow(a: ConsistentAction): ConsistentActionRow {
  return {
    id: a.id,
    target_id: a.targetId,
    start_time: a.startTime,
    end_time: a.endTime,
    recurrence: a.recurrence,
    start_date: a.startDate,
    created_at: a.createdAt,
    updated_at: a.updatedAt,
    deleted_at: a.deletedAt,
  };
}

export function rowToConsistentAction(r: ConsistentActionRow): ConsistentAction {
  return {
    id: r.id,
    targetId: r.target_id,
    startTime: r.start_time,
    endTime: r.end_time,
    recurrence: r.recurrence,
    startDate: dayOrNull(r.start_date),
    createdAt: toIsoMillis(r.created_at),
    updatedAt: toIsoMillis(r.updated_at),
    deletedAt: tsOrNull(r.deleted_at),
  };
}

export function sessionMarkToRow(m: SessionMark): SessionMarkRow {
  return {
    action_id: m.actionId,
    date: m.date,
    attended: m.attended,
    updated_at: m.updatedAt,
    deleted_at: m.deletedAt,
  };
}

export function rowToSessionMark(r: SessionMarkRow): SessionMark {
  const date = day(r.date);
  return {
    id: sessionMarkId(r.action_id, date),
    actionId: r.action_id,
    date,
    attended: r.attended,
    updatedAt: toIsoMillis(r.updated_at),
    deletedAt: tsOrNull(r.deleted_at),
  };
}
