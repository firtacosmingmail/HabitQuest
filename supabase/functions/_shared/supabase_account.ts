/**
 * Real implementations of the account interfaces (see account.ts).
 *
 * Reads and writes of the user's rows go through a client built from the
 * anon key plus the caller's JWT, so row-level security applies. Only
 * `account-delete` uses the service role key, for auth.admin.deleteUser; the
 * key comes from the function environment (SUPABASE_SERVICE_ROLE_KEY, set by
 * Supabase for deployed functions), stays server-side and is never logged
 * or returned.
 */
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import type {
  AccountDeleter,
  AccountUser,
  CallerContext,
  PasswordGateway,
  ProfileRow,
  ProfileStore,
} from "./account.ts";
import { providersOf } from "./account.ts";
import { ApiError, mapDbError, unauthorized } from "./errors.ts";
import { anonClient, bearerToken, type Env, readEnv, userClient } from "./supabase.ts";
import { toIsoMillis } from "./validation.ts";

const authErr = (e: { status?: number; code?: string; message?: string }) => ({
  status: e.status,
  code: e.code,
  message: e.message,
});

/** Caller context + their RLS-bound client. */
export interface SupabaseCaller extends CallerContext {
  client: SupabaseClient;
}

/** Validates the bearer token with auth.getUser (the user's own token). */
export async function authenticateAccount(req: Request): Promise<SupabaseCaller> {
  const token = bearerToken(req);
  if (!token) throw unauthorized("Missing bearer token");
  const client = userClient(readEnv(req), token);
  const { data, error } = await client.auth.getUser(token);
  if (error || !data?.user) {
    if (error && (error.status ?? 0) >= 500) {
      console.error("auth.getUser failed", { status: error.status, code: error.code });
      throw new ApiError(500, "internal_error", "Auth service error");
    }
    throw unauthorized();
  }
  const u = data.user;
  const user: AccountUser = {
    id: u.id,
    email: u.email ?? null,
    createdAt: u.created_at ? toIsoMillis(u.created_at) : "",
    providers: providersOf(u.identities, u.app_metadata?.providers),
  };
  return { user, token, client };
}

interface ProfileDbRow {
  display_name: string | null;
  created_at: string | null;
}

const toProfile = (r: ProfileDbRow): ProfileRow => ({
  displayName: r.display_name,
  createdAt: r.created_at ? toIsoMillis(r.created_at) : null,
});

export function profileStore(client: SupabaseClient): ProfileStore {
  return {
    async get(userId) {
      const { data, error } = await client
        .from("profiles")
        .select("display_name, created_at")
        .eq("id", userId)
        .maybeSingle();
      if (error) throw mapDbError(error);
      return data ? toProfile(data as ProfileDbRow) : null;
    },
    async setDisplayName(userId, displayName) {
      const { data, error } = await client
        .from("profiles")
        .upsert({ id: userId, display_name: displayName }, { onConflict: "id" })
        .select("display_name, created_at")
        .single();
      if (error) throw mapDbError(error);
      return toProfile(data as ProfileDbRow);
    },
  };
}

/** See [PasswordGateway]: one anon client per request. */
export function supabasePasswordGateway(env: Env): PasswordGateway {
  const client = anonClient(env);
  return {
    async verify(email, password) {
      const { data, error } = await client.auth.signInWithPassword({ email, password });
      if (error) return { error: authErr(error) };
      if (!data.session) return { error: { status: 400, code: "invalid_credentials" } };
      return { error: null };
    },
    async update(newPassword) {
      const { error } = await client.auth.updateUser({ password: newPassword });
      // Drop the short-lived session the verification created.
      await client.auth.signOut({ scope: "local" }).catch(() => undefined);
      return { error: error ? authErr(error) : null };
    },
  };
}

/** Service-role client, built only inside account-delete. */
function serviceClient(env: Env): SupabaseClient {
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!key) throw new ApiError(500, "internal_error", "Server is not configured");
  return createClient(env.url, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

/** Tables to empty, children first. */
const USER_TABLES: { table: string; column: string }[] = [
  { table: "check_ins", column: "user_id" },
  { table: "habits", column: "user_id" },
  { table: "game_state", column: "user_id" },
  { table: "profiles", column: "id" },
];

export function supabaseAccountDeleter(env: Env, caller: SupabaseClient): AccountDeleter {
  return {
    async deleteData(userId) {
      for (const { table, column } of USER_TABLES) {
        const { error } = await caller.from(table).delete().eq(column, userId);
        if (error) throw mapDbError(error);
      }
    },
    async deleteAuthUser(userId) {
      const { error } = await serviceClient(env).auth.admin.deleteUser(userId);
      if (error) {
        console.error("auth.admin.deleteUser failed", { status: error.status, code: error.code });
        throw new ApiError(500, "internal_error", "Could not delete the account");
      }
    },
  };
}
