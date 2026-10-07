// check-ins CRUD with last-write-wins and tombstones (see supabase/API.md)
import { withHttp } from "../_shared/http.ts";
import { checkInsSpec, handleResource } from "../_shared/resource.ts";
import { authenticate, checkInStore } from "../_shared/supabase.ts";

Deno.serve(withHttp(async (req) => {
  const caller = await authenticate(req);
  return handleResource(req, checkInsSpec, checkInStore(caller.client));
}));
