// admin-quotes: every quote with love counts, search, date filter, delete (see supabase/API.md)
import { withHttp } from "../_shared/http.ts";
import { handleAdminQuotes } from "../_shared/admin_quotes.ts";
import { adminEmails, adminQuoteStore, authenticateAdmin } from "../_shared/supabase_admin.ts";

Deno.serve(
  withHttp((req) =>
    handleAdminQuotes(req, {
      authenticate: authenticateAdmin,
      store: () => adminQuoteStore(req),
      admins: adminEmails,
    })
  ),
);
