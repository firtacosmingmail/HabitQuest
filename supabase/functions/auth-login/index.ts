// POST auth-login {email,password} → {session} (see supabase/API.md)
import { handleLogin } from "../_shared/auth.ts";
import { withHttp } from "../_shared/http.ts";
import { readEnv } from "../_shared/supabase.ts";
import { supabaseAuthGateway } from "../_shared/supabase_auth.ts";

Deno.serve(withHttp((req) => handleLogin(req, supabaseAuthGateway(readEnv(req)))));
