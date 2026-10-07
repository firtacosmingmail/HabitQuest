// POST auth-refresh {refreshToken} → {session} (see supabase/API.md)
import { handleRefresh } from "../_shared/auth.ts";
import { withHttp } from "../_shared/http.ts";
import { readEnv } from "../_shared/supabase.ts";
import { supabaseAuthGateway } from "../_shared/supabase_auth.ts";

Deno.serve(withHttp((req) => handleRefresh(req, supabaseAuthGateway(readEnv(req)))));
