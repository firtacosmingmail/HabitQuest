// auth-change-password POST {currentPassword, newPassword} (see supabase/API.md)
import { handleChangePassword } from "../_shared/account.ts";
import { withHttp } from "../_shared/http.ts";
import { readEnv } from "../_shared/supabase.ts";
import { authenticateAccount, supabasePasswordGateway } from "../_shared/supabase_account.ts";

Deno.serve(
  withHttp((req) =>
    handleChangePassword(req, authenticateAccount, supabasePasswordGateway(readEnv(req)))
  ),
);
