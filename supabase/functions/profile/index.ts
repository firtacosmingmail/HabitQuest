// profile GET/PUT for the caller (see supabase/API.md)
import { handleProfile } from "../_shared/account.ts";
import { withHttp } from "../_shared/http.ts";
import { authenticateAccount, profileStore } from "../_shared/supabase_account.ts";

Deno.serve(
  withHttp((req) => handleProfile(req, authenticateAccount, (c) => profileStore(c.client))),
);
