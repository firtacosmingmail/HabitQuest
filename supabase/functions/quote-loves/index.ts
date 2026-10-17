// quote-loves: the caller's saved quotes (see supabase/API.md)
import { withHttp } from "../_shared/http.ts";
import { handleQuoteLoves } from "../_shared/quotes.ts";
import { authenticateQuotes, loveStore } from "../_shared/supabase_quotes.ts";

Deno.serve(
  withHttp((req) => handleQuoteLoves(req, { authenticate: authenticateQuotes, store: loveStore })),
);
