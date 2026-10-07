/** HTTP handler for the `game-state` function (storage behind an interface). */
import { json, methodNotAllowed, noContent, notFound } from "./errors.ts";
import { readJsonObject, subPath } from "./http.ts";
import { validateGameState } from "./validation.ts";
import type { GameState, WriteResult } from "./types.ts";

export interface GameStateStore {
  get(): Promise<GameState | null>;
  upsert(gs: GameState): Promise<WriteResult<GameState>>;
  reset(): Promise<void>;
}

export async function handleGameState(
  req: Request,
  store: GameStateStore,
  now: () => Date = () => new Date(),
): Promise<Response> {
  const url = new URL(req.url);
  if (subPath(url, "game-state").length > 0) {
    throw notFound(`Unknown route ${url.pathname}`);
  }
  const method = req.method.toUpperCase();
  switch (method) {
    case "GET":
      return json({ item: await store.get(), serverTime: now().toISOString() });
    case "PUT":
      return json(await store.upsert(validateGameState(await readJsonObject(req))));
    case "DELETE":
      await store.reset();
      return noContent();
    default:
      throw methodNotAllowed(method);
  }
}
