// account-delete POST {confirm:"DELETE"}: deletes the caller's data and auth user
// (see supabase/API.md). The user id comes from the verified JWT only.
import { handleAccountDelete } from "../_shared/account.ts";
import { withHttp } from "../_shared/http.ts";
import { readEnv } from "../_shared/supabase.ts";
import { authenticateAccount, supabaseAccountDeleter } from "../_shared/supabase_account.ts";

Deno.serve(
  withHttp((req) =>
    handleAccountDelete(
      req,
      authenticateAccount,
      (c) => supabaseAccountDeleter(readEnv(req), c.client),
    )
  ),
);
