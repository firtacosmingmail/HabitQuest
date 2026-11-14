/**
 * Supabase client creation, caller authentication and the SQL-backed stores.
 *
 * The Projects stores (projects, targets, plan tasks, consistent actions,
 * session marks) use the same SQL-backed LWW store as habits and check-ins.
 *
 * Data access always goes through a client created with the anon key plus
 * the caller's JWT, so row-level security applies. The service role key is
 * used only by account-delete's auth.admin.deleteUser (supabase_account.ts)
 * by the admin-only quote writes (supabase_quotes.ts), and by the signed-out
 * (no Authorization header) quote reads of the `quotes` GET, whose handler
 * filters out future quotes (supabase_quotes.ts, quotes.ts).
 */
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { ApiError, mapDbError, parentNotFound, unauthorized } from "./errors.ts";
import {
  type ConsistentActionRow,
  consistentActionToRow,
  type PlanTaskRow,
  planTaskToRow,
  type ProjectRow,
  projectToRow,
  rowToConsistentAction,
  rowToPlanTask,
  rowToProject,
  rowToSessionMark,
  rowToTarget,
  type SessionMarkRow,
  sessionMarkToRow,
  type TargetRow,
  targetToRow,
} from "./projects_mapping.ts";
import { parseSessionMarkId } from "./projects_validation.ts";
import {
  type CheckInRow,
  checkInToRow,
  type GameStateRow,
  type HabitRow,
  habitToRow,
  rowToCheckIn,
  rowToGameState,
  rowToHabit,
} from "./mapping.ts";
import type { ListQuery, ResourceStore } from "./resource.ts";
import type { GameStateStore } from "./game_state.ts";
import type {
  BatchResult,
  CheckIn,
  ConsistentAction,
  GameState,
  Habit,
  PlanTask,
  Project,
  SessionMark,
  Target,
  WriteResult,
} from "./types.ts";
import { toIsoMillis } from "./validation.ts";

export interface Env {
  url: string;
  anonKey: string;
}

/** SUPABASE_URL / SUPABASE_ANON_KEY are injected by the Edge Runtime. */
export function readEnv(req?: Request): Env {
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    req?.headers.get("apikey") ?? undefined;
  if (!url || !anonKey) {
    throw new ApiError(500, "internal_error", "Server is not configured");
  }
  return { url, anonKey };
}

const clientOptions = {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false,
  },
};

/** Anonymous client (auth endpoints). */
export function anonClient(env: Env): SupabaseClient {
  return createClient(env.url, env.anonKey, clientOptions);
}

/** Client acting as the caller: anon key + the caller's JWT (RLS applies). */
export function userClient(env: Env, accessToken: string): SupabaseClient {
  return createClient(env.url, env.anonKey, {
    ...clientOptions,
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  });
}

/** Extracts the bearer token, or null. */
export function bearerToken(req: Request): string | null {
  const header = req.headers.get("authorization") ?? "";
  const m = /^Bearer\s+(.+)$/i.exec(header.trim());
  return m ? m[1].trim() : null;
}

export interface Caller {
  userId: string;
  email: string | null;
  token: string;
  client: SupabaseClient;
}

/** Validates the caller's token with Supabase Auth or throws 401. */
export async function authenticate(req: Request): Promise<Caller> {
  const token = bearerToken(req);
  if (!token) throw unauthorized("Missing bearer token");
  const env = readEnv(req);
  const client = userClient(env, token);
  const { data, error } = await client.auth.getUser(token);
  if (error || !data?.user) {
    if (error && (error.status ?? 0) >= 500) {
      console.error("auth.getUser failed", error);
      throw new ApiError(500, "internal_error", "Auth service error");
    }
    throw unauthorized();
  }
  return {
    userId: data.user.id,
    email: data.user.email ?? null,
    token,
    client,
  };
}

async function rpc<T>(
  client: SupabaseClient,
  fn: string,
  args: Record<string, unknown>,
  foreignKey?: ApiError,
): Promise<T> {
  const { data, error } = await client.rpc(fn, args);
  if (error) throw mapDbError(error, foreignKey);
  return data as T;
}

interface RawWrite<R> {
  applied: boolean;
  item: R;
}

interface SqlResourceConfig<T, R> {
  table: string;
  toRow(item: T): R;
  fromRow(row: R): T;
  pull: string;
  upsert: string;
  upsertMany: string;
  softDelete: string;
  pullArgs(q: ListQuery): Record<string, unknown>;
  /** Column filter of GET /<id> (default `{ id }`). */
  match?(id: string): Record<string, string>;
  /** Key arguments of the soft delete function (default `{ p_id: id }`). */
  deleteArgs?(id: string): Record<string, unknown>;
  /** Error for a foreign key violation (child pushed before its parent). */
  foreignKey?: ApiError;
}

class SqlResourceStore<T, R> implements ResourceStore<T> {
  constructor(
    private readonly client: SupabaseClient,
    private readonly cfg: SqlResourceConfig<T, R>,
  ) {}

  async list(q: ListQuery) {
    const data = await rpc<{ items: R[]; server_time: string }>(
      this.client,
      this.cfg.pull,
      this.cfg.pullArgs(q),
    );
    return {
      items: (data.items ?? []).map((r) => this.cfg.fromRow(r)),
      serverTime: toIsoMillis(data.server_time),
    };
  }

  async get(id: string): Promise<T | null> {
    const { data, error } = await this.client
      .from(this.cfg.table)
      .select("*")
      .match(this.cfg.match ? this.cfg.match(id) : { id })
      .maybeSingle();
    if (error) throw mapDbError(error);
    return data ? this.cfg.fromRow(data as R) : null;
  }

  async upsert(item: T): Promise<WriteResult<T>> {
    const r = await rpc<RawWrite<R>>(this.client, this.cfg.upsert, {
      p_item: this.cfg.toRow(item),
    }, this.cfg.foreignKey);
    return { item: this.cfg.fromRow(r.item), applied: r.applied };
  }

  async upsertMany(items: T[]): Promise<BatchResult<T>[]> {
    if (items.length === 0) return [];
    const rs = await rpc<(RawWrite<R> & { id: string })[]>(
      this.client,
      this.cfg.upsertMany,
      { p_items: items.map((i) => this.cfg.toRow(i)) },
      this.cfg.foreignKey,
    );
    return rs.map((r) => ({
      id: r.id,
      applied: r.applied,
      item: this.cfg.fromRow(r.item),
    }));
  }

  async softDelete(id: string, updatedAt: string | null) {
    const r = await rpc<RawWrite<R> | null>(this.client, this.cfg.softDelete, {
      ...(this.cfg.deleteArgs ? this.cfg.deleteArgs(id) : { p_id: id }),
      p_updated_at: updatedAt,
    });
    return r ? { item: this.cfg.fromRow(r.item), applied: r.applied } : null;
  }
}

export function habitStore(client: SupabaseClient): ResourceStore<Habit> {
  return new SqlResourceStore<Habit, HabitRow>(client, {
    table: "habits",
    toRow: habitToRow,
    fromRow: rowToHabit,
    pull: "pull_habits",
    upsert: "upsert_habit",
    upsertMany: "upsert_habits",
    softDelete: "soft_delete_habit",
    pullArgs: (q) => ({ p_since: q.since }),
  });
}

export function checkInStore(client: SupabaseClient): ResourceStore<CheckIn> {
  return new SqlResourceStore<CheckIn, CheckInRow>(client, {
    table: "check_ins",
    toRow: checkInToRow,
    fromRow: rowToCheckIn,
    pull: "pull_check_ins",
    upsert: "upsert_check_in",
    upsertMany: "upsert_check_ins",
    softDelete: "soft_delete_check_in",
    pullArgs: (q) => ({ p_since: q.since, p_habit_id: q.parentId }),
  });
}

// Projects -------------------------------------------------------------------

const pushParentFirst = (child: string, parent: string) =>
  parentNotFound(
    `The ${parent} of this ${child} does not exist on the server; push the ${parent} first`,
  );

export function projectStore(client: SupabaseClient): ResourceStore<Project> {
  return new SqlResourceStore<Project, ProjectRow>(client, {
    table: "projects",
    toRow: projectToRow,
    fromRow: rowToProject,
    pull: "pull_projects",
    upsert: "upsert_project",
    upsertMany: "upsert_projects",
    softDelete: "soft_delete_project",
    pullArgs: (q) => ({ p_since: q.since }),
  });
}

export function targetStore(client: SupabaseClient): ResourceStore<Target> {
  return new SqlResourceStore<Target, TargetRow>(client, {
    table: "targets",
    toRow: targetToRow,
    fromRow: rowToTarget,
    pull: "pull_targets",
    upsert: "upsert_target",
    upsertMany: "upsert_targets",
    softDelete: "soft_delete_target",
    pullArgs: (q) => ({ p_since: q.since, p_project_id: q.parentId }),
    foreignKey: pushParentFirst("target", "project"),
  });
}

export function planTaskStore(client: SupabaseClient): ResourceStore<PlanTask> {
  return new SqlResourceStore<PlanTask, PlanTaskRow>(client, {
    table: "plan_tasks",
    toRow: planTaskToRow,
    fromRow: rowToPlanTask,
    pull: "pull_plan_tasks",
    upsert: "upsert_plan_task",
    upsertMany: "upsert_plan_tasks",
    softDelete: "soft_delete_plan_task",
    pullArgs: (q) => ({ p_since: q.since, p_target_id: q.parentId }),
    foreignKey: pushParentFirst("plan task", "target"),
  });
}

export function consistentActionStore(client: SupabaseClient): ResourceStore<ConsistentAction> {
  return new SqlResourceStore<ConsistentAction, ConsistentActionRow>(client, {
    table: "consistent_actions",
    toRow: consistentActionToRow,
    fromRow: rowToConsistentAction,
    pull: "pull_consistent_actions",
    upsert: "upsert_consistent_action",
    upsertMany: "upsert_consistent_actions",
    softDelete: "soft_delete_consistent_action",
    pullArgs: (q) => ({ p_since: q.since, p_target_id: q.parentId }),
    foreignKey: pushParentFirst("consistent action", "target"),
  });
}

/** Keyed by (action_id, date); the API id is `<actionId>|<yyyy-MM-dd>`. */
export function sessionMarkStore(client: SupabaseClient): ResourceStore<SessionMark> {
  return new SqlResourceStore<SessionMark, SessionMarkRow>(client, {
    table: "session_marks",
    toRow: sessionMarkToRow,
    fromRow: rowToSessionMark,
    pull: "pull_session_marks",
    upsert: "upsert_session_mark",
    upsertMany: "upsert_session_marks",
    softDelete: "soft_delete_session_mark",
    pullArgs: (q) => ({ p_since: q.since, p_action_id: q.parentId }),
    match: (id) => {
      const k = parseSessionMarkId(id);
      return { action_id: k.actionId, date: k.date };
    },
    deleteArgs: (id) => {
      const k = parseSessionMarkId(id);
      return { p_action_id: k.actionId, p_date: k.date };
    },
    foreignKey: pushParentFirst("session mark", "consistent action"),
  });
}

export function gameStateStore(client: SupabaseClient, userId: string): GameStateStore {
  return {
    async get() {
      const { data, error } = await client
        .from("game_state")
        .select("*")
        .eq("user_id", userId)
        .maybeSingle();
      if (error) throw mapDbError(error);
      return data ? rowToGameState(data as GameStateRow) : null;
    },
    async upsert(gs: GameState) {
      const r = await rpc<RawWrite<GameStateRow>>(client, "upsert_game_state", {
        p_state: gs.state,
        p_updated_at: gs.updatedAt,
      });
      return { item: rowToGameState(r.item), applied: r.applied };
    },
    async reset() {
      const { error } = await client
        .from("game_state")
        .delete()
        .eq("user_id", userId);
      if (error) throw mapDbError(error);
    },
  };
}
