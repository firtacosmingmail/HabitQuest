// plan-tasks CRUD with last-write-wins and tombstones (see supabase/API.md "Projects")
import { withHttp } from "../_shared/http.ts";
import { handleResource, planTasksSpec } from "../_shared/resource.ts";
import { authenticate, planTaskStore } from "../_shared/supabase.ts";

Deno.serve(withHttp(async (req) => {
  const caller = await authenticate(req);
  return handleResource(req, planTasksSpec, planTaskStore(caller.client));
}));
