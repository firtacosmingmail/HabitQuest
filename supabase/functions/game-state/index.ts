// game-state GET/PUT (last-write-wins)/DELETE (see supabase/API.md)
import { handleGameState } from "../_shared/game_state.ts";
import { withHttp } from "../_shared/http.ts";
import { authenticate, gameStateStore } from "../_shared/supabase.ts";

Deno.serve(withHttp(async (req) => {
  const caller = await authenticate(req);
  return handleGameState(req, gameStateStore(caller.client, caller.userId));
}));
