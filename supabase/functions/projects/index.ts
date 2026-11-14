// projects CRUD with last-write-wins and tombstones (see supabase/API.md "Projects")
import { withHttp } from "../_shared/http.ts";
import { handleResource, projectsSpec } from "../_shared/resource.ts";
import { authenticate, projectStore } from "../_shared/supabase.ts";

Deno.serve(withHttp(async (req) => {
  const caller = await authenticate(req);
  return handleResource(req, projectsSpec, projectStore(caller.client));
}));
