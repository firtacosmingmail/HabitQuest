import { assertEquals } from "jsr:@std/assert@1";
import { handleGameState } from "../_shared/game_state.ts";
import { withHttp } from "../_shared/http.ts";
import { MemoryGameStateStore, req } from "./fakes.ts";

const now = () => new Date("2026-10-07T12:00:00.000Z");

function setup() {
  const store = new MemoryGameStateStore();
  return { store, g: withHttp((r) => handleGameState(r, store, now)) };
}

Deno.test("GET with no state → item null and serverTime", async () => {
  const { g } = setup();
  const res = await g(req("GET", "game-state"));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { item: null, serverTime: "2026-10-07T12:00:00.000Z" });
});

Deno.test("PUT is LWW, GET returns the stored state", async () => {
  const { g } = setup();
  const v1 = { state: { xp: 10 }, updatedAt: "2026-10-07T10:00:00.000Z" };
  let res = await g(req("PUT", "game-state", v1));
  assertEquals(await res.json(), { item: v1, applied: true });

  res = await g(req("PUT", "game-state", { state: { xp: 1 }, updatedAt: "2026-10-07T09:00:00Z" }));
  assertEquals(await res.json(), { item: v1, applied: false });

  res = await g(req("GET", "game-state"));
  assertEquals((await res.json()).item, v1);
});

Deno.test("PUT validates; DELETE resets with 204", async () => {
  const { g, store } = setup();
  let res = await g(req("PUT", "game-state", { state: "x", updatedAt: "2026-10-07T09:00:00Z" }));
  assertEquals(res.status, 400);
  await g(req("PUT", "game-state", { state: {}, updatedAt: "2026-10-07T09:00:00Z" }));
  res = await g(req("DELETE", "game-state"));
  assertEquals(res.status, 204);
  assertEquals(await res.text(), "");
  assertEquals(store.value, null);
  assertEquals((await g(req("POST", "game-state", {}))).status, 405);
  assertEquals((await g(req("GET", "game-state/x"))).status, 404);
});
