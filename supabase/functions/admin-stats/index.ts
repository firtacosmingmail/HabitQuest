// admin-stats: read-only aggregated usage stats + the admin sign-in check (see supabase/API.md)
import { withHttp } from "../_shared/http.ts";
import { handleAdminStats } from "../_shared/admin_stats.ts";
import { adminEmails, authenticateAdmin, statsStore } from "../_shared/supabase_admin.ts";

Deno.serve(
  withHttp((req) =>
    handleAdminStats(req, {
      authenticate: authenticateAdmin,
      store: () => statsStore(req),
      admins: adminEmails,
    })
  ),
);
