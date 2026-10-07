// POST auth-logout (Bearer) → 204 (see supabase/API.md)
import { handleLogout } from "../_shared/auth.ts";
import { withHttp } from "../_shared/http.ts";
import { bearerToken, readEnv } from "../_shared/supabase.ts";
import { supabaseAuthGateway } from "../_shared/supabase_auth.ts";

Deno.serve(
  withHttp((req) => handleLogout(req, supabaseAuthGateway(readEnv(req)), bearerToken)),
);
