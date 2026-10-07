// POST auth-register {email,password,displayName?} → {session} (see supabase/API.md)
import { handleRegister } from "../_shared/auth.ts";
import { withHttp } from "../_shared/http.ts";
import { readEnv } from "../_shared/supabase.ts";
import { supabaseAuthGateway } from "../_shared/supabase_auth.ts";

Deno.serve(withHttp((req) => handleRegister(req, supabaseAuthGateway(readEnv(req)))));
