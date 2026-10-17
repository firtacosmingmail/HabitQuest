// quotes: quote of the day, history, admin create/update (see supabase/API.md)
import { withHttp } from "../_shared/http.ts";
import { handleQuotes } from "../_shared/quotes.ts";
import { authenticateQuotes, quoteAdmins, quoteStore } from "../_shared/supabase_quotes.ts";

Deno.serve(
  withHttp((req) =>
    handleQuotes(req, {
      authenticate: authenticateQuotes,
      store: (c) => quoteStore(c, req),
      admins: quoteAdmins,
    })
  ),
);
