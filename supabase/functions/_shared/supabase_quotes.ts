/**
 * Real implementations of the quote interfaces (see quotes.ts).
 *
 * Reads go through the caller's client (anon key + their JWT, so RLS
 * applies). Writes to `quotes` use a service-role client, created only after
 * the handler has checked that the caller is an admin. The service role key
 * comes from the function environment (SUPABASE_SERVICE_ROLE_KEY), stays
 * server-side and is never logged or returned.
 */
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { ApiError, type DbError, mapDbError } from "./errors.ts";
import {
  dayTaken,
  type LovedQuote,
  type LoveStore,
  type Quote,
  type QuoteCaller,
  type QuoteStore,
} from "./quotes.ts";
import { authenticate, bearerToken, readEnv } from "./supabase.ts";
import { envAdmins } from "./admin.ts";
import { toIsoMillis } from "./validation.ts";
import type { QuoteInput, QuotePatch } from "./validation.ts";

export interface SupabaseQuoteCaller extends QuoteCaller {
  /** RLS-bound user client, or the service-role client. */
  client: SupabaseClient;
}

const clientOptions = {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
};

function serviceKey(): string | null {
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? null;
}

/** Service-role client: only after the caller passed the admin check. */
export function serviceClient(req?: Request): SupabaseClient {
  const key = serviceKey();
  if (!key) throw new ApiError(500, "internal_error", "Server is not configured");
  return createClient(readEnv(req).url, key, clientOptions);
}

/** Constant-time string comparison. */
function sameSecret(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

/** Service role (bearer = SUPABASE_SERVICE_ROLE_KEY) or a verified user. */
export async function authenticateQuotes(req: Request): Promise<SupabaseQuoteCaller> {
  const token = bearerToken(req);
  const key = serviceKey();
  if (token && key && sameSecret(token, key)) {
    return { userId: null, email: null, serviceRole: true, client: serviceClient(req) };
  }
  const c = await authenticate(req);
  return { userId: c.userId, email: c.email, serviceRole: false, client: c.client };
}

/** The admin emails (QUOTE_ADMINS); see admin.ts. */
export const quoteAdmins = envAdmins;

interface QuoteRow {
  id: string;
  text: string;
  author: string | null;
  day: string | null;
  created_at: string;
  updated_at: string;
}

const toQuote = (r: QuoteRow): Quote => ({
  id: r.id,
  text: r.text,
  author: r.author,
  day: r.day,
  createdAt: toIsoMillis(r.created_at),
  updatedAt: toIsoMillis(r.updated_at),
});

function writeError(err: DbError, day: string | null | undefined): ApiError {
  if (err.code === "23505" && day) return dayTaken(day);
  return mapDbError(err);
}

export function quoteStore(caller: SupabaseQuoteCaller, req?: Request): QuoteStore {
  const db = caller.client;
  const candidates = (before: string | null) => {
    const q = db.from("quotes").select("*", { count: "exact" });
    return before === null ? q : q.lt("day", before);
  };
  return {
    async byDay(day) {
      const { data, error } = await db.from("quotes").select("*").eq("day", day).maybeSingle();
      if (error) throw mapDbError(error);
      return data ? toQuote(data as QuoteRow) : null;
    },
    async count(before) {
      const q = db.from("quotes").select("id", { count: "exact", head: true });
      const { count, error } = await (before === null ? q : q.lt("day", before));
      if (error) throw mapDbError(error);
      return count ?? 0;
    },
    async nth(before, index) {
      const { data, error } = await candidates(before)
        .order("day", { ascending: true, nullsFirst: false })
        .order("id", { ascending: true })
        .range(index, index);
      if (error) throw mapDbError(error);
      const rows = (data ?? []) as QuoteRow[];
      return rows.length > 0 ? toQuote(rows[0]) : null;
    },
    async range(from, to) {
      const { data, error } = await db.from("quotes").select("*")
        .gte("day", from).lte("day", to)
        .order("day", { ascending: false });
      if (error) throw mapDbError(error);
      return ((data ?? []) as QuoteRow[]).map(toQuote);
    },
    async create(input: QuoteInput) {
      const { data, error } = await serviceClient(req).from("quotes")
        .insert({ text: input.text, author: input.author, day: input.day })
        .select("*").single();
      if (error) throw writeError(error, input.day);
      return toQuote(data as QuoteRow);
    },
    async update(id: string, patch: QuotePatch) {
      const { data, error } = await serviceClient(req).from("quotes")
        .update(patch).eq("id", id).select("*").maybeSingle();
      if (error) throw writeError(error, patch.day);
      return data ? toQuote(data as QuoteRow) : null;
    },
    async lovedIds(ids) {
      if (caller.userId === null || ids.length === 0) return new Set<string>();
      const { data, error } = await db.from("quote_loves").select("quote_id")
        .eq("user_id", caller.userId).in("quote_id", ids);
      if (error) throw mapDbError(error);
      return new Set(((data ?? []) as { quote_id: string }[]).map((r) => r.quote_id));
    },
  };
}

interface LoveRow {
  created_at: string;
  quote: QuoteRow | null;
}

const toLoved = (r: LoveRow): LovedQuote | null =>
  r.quote ? { quote: toQuote(r.quote), lovedAt: toIsoMillis(r.created_at) } : null;

export function loveStore(caller: SupabaseQuoteCaller): LoveStore {
  const db = caller.client;
  const userId = caller.userId!;
  const select = "created_at, quote:quotes(*)";
  return {
    async list() {
      const { data, error } = await db.from("quote_loves").select(select)
        .eq("user_id", userId)
        .order("created_at", { ascending: false })
        .order("quote_id", { ascending: true });
      if (error) throw mapDbError(error);
      return ((data ?? []) as unknown as LoveRow[]).map(toLoved).filter((l) => l !== null);
    },
    async love(quoteId) {
      const { error } = await db.from("quote_loves")
        .upsert({ user_id: userId, quote_id: quoteId }, {
          onConflict: "user_id,quote_id",
          ignoreDuplicates: true,
        });
      if (error) {
        if (error.code === "23503") return null; // unknown quote
        throw mapDbError(error);
      }
      const { data, error: readError } = await db.from("quote_loves").select(select)
        .eq("user_id", userId).eq("quote_id", quoteId).maybeSingle();
      if (readError) throw mapDbError(readError);
      return data ? toLoved(data as unknown as LoveRow) : null;
    },
    async unlove(quoteId) {
      const { error } = await db.from("quote_loves").delete()
        .eq("user_id", userId).eq("quote_id", quoteId);
      if (error) throw mapDbError(error);
    },
  };
}
