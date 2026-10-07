// habits CRUD with last-write-wins and tombstones (see supabase/API.md)
import { withHttp } from "../_shared/http.ts";
import { habitsSpec, handleResource } from "../_shared/resource.ts";
import { authenticate, habitStore } from "../_shared/supabase.ts";

Deno.serve(withHttp(async (req) => {
  const caller = await authenticate(req);
  return handleResource(req, habitsSpec, habitStore(caller.client));
}));
