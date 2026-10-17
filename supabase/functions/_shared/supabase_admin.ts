/**
 * Real stores for `admin-quotes` and `admin-stats` (see admin_quotes.ts and
 * admin_stats.ts).
 *
 * Both use the service-role client: the handlers create a store only after
 * requireAdmin has passed, and the SQL functions they call
 * (migration 20261017120000_admin_functions.sql) are executable by the
 * service role only. The key comes from SUPABASE_SERVICE_ROLE_KEY, stays
 * server-side and is never logged or returned.
 */
import type { AdminQuoteStore, QuotePage } from "./admin_quotes.ts";
import type { RawStats, StatsStore } from "./admin_stats.ts";
import { mapDbError } from "./errors.ts";
import { serviceClient } from "./supabase_quotes.ts";
import { toIsoMillis } from "./validation.ts";

export { authenticateQuotes as authenticateAdmin } from "./supabase_quotes.ts";
export { envAdmins as adminEmails } from "./admin.ts";

interface AdminQuoteRow {
  id: string;
  text: string;
  author: string | null;
  day: string | null;
  created_at: string;
  updated_at: string;
  loves: number;
}

export function adminQuoteStore(req?: Request): AdminQuoteStore {
  return {
    async search(s) {
      const { data, error } = await serviceClient(req).rpc("admin_list_quotes", {
        p_query: s.query,
        p_from: s.from,
        p_to: s.to,
        p_scheduled: s.scheduled,
        p_limit: s.limit,
        p_offset: s.offset,
      });
      if (error) throw mapDbError(error);
      const page = data as { total: number; items: AdminQuoteRow[] };
      return {
        total: Number(page.total ?? 0),
        items: (page.items ?? []).map((r) => ({
          id: r.id,
          text: r.text,
          author: r.author,
          day: r.day,
          createdAt: toIsoMillis(r.created_at),
          updatedAt: toIsoMillis(r.updated_at),
          loves: Number(r.loves ?? 0),
        })),
      } satisfies QuotePage;
    },
    async delete(id) {
      const { data, error } = await serviceClient(req).from("quotes").delete().eq("id", id)
        .select("id");
      if (error) throw mapDbError(error);
      return (data ?? []).length > 0;
    },
  };
}

export function statsStore(req?: Request): StatsStore {
  return {
    async raw(from, to) {
      const { data, error } = await serviceClient(req).rpc("admin_stats", {
        p_from: from,
        p_to: to,
      });
      if (error) throw mapDbError(error);
      return data as RawStats;
    },
  };
}
