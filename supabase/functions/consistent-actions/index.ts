// consistent-actions CRUD with last-write-wins and tombstones (see supabase/API.md "Projects")
import { withHttp } from "../_shared/http.ts";
import { consistentActionsSpec, handleResource } from "../_shared/resource.ts";
import { authenticate, consistentActionStore } from "../_shared/supabase.ts";

Deno.serve(withHttp(async (req) => {
  const caller = await authenticate(req);
  return handleResource(req, consistentActionsSpec, consistentActionStore(caller.client));
}));
