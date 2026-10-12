// POST auth-oauth {provider,idToken,nonce?} → {session} (see supabase/API.md)
import { handleOAuth } from "../_shared/auth.ts";
import { withHttp } from "../_shared/http.ts";
import { readEnv } from "../_shared/supabase.ts";
import { supabaseAuthGateway } from "../_shared/supabase_auth.ts";

Deno.serve(withHttp((req) => handleOAuth(req, supabaseAuthGateway(readEnv(req)))));
