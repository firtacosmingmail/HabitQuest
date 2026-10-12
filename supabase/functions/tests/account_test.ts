import { assertEquals } from "jsr:@std/assert@1";
import {
  type AccountDeleter,
  type AccountUser,
  type Authenticate,
  type CallerContext,
  handleAccountDelete,
  handleChangePassword,
  handleProfile,
  type PasswordGateway,
  type ProfileRow,
  type ProfileStore,
  providersOf,
  validateDisplayName,
} from "../_shared/account.ts";
import { unauthorized } from "../_shared/errors.ts";
import { withHttp } from "../_shared/http.ts";
import { req } from "./fakes.ts";

const alice: AccountUser = {
  id: "user-alice",
  email: "alice@example.com",
  createdAt: "2026-10-01T08:00:00.000Z",
  providers: ["email"],
};
const googler: AccountUser = { ...alice, id: "user-g", providers: ["google"] };

const auth = { authorization: "Bearer good" };

/** Accepts only "Bearer good" and returns [user]. */
function fakeAuth(user: AccountUser): Authenticate & { calls: number } {
  const fn = (r: Request): Promise<CallerContext> => {
    fn.calls++;
    if (r.headers.get("authorization") !== "Bearer good") {
      return Promise.reject(unauthorized());
    }
    return Promise.resolve({ user, token: "good" });
  };
  fn.calls = 0;
  return fn;
}

class MemoryProfiles implements ProfileStore {
  rows = new Map<string, ProfileRow>();
  get(id: string) {
    return Promise.resolve(this.rows.get(id) ?? null);
  }
  setDisplayName(id: string, displayName: string) {
    const row = { createdAt: "2026-10-01T08:00:01.000Z", ...this.rows.get(id), displayName };
    this.rows.set(id, row);
    return Promise.resolve(row);
  }
}

const json = (body: unknown) => body as Record<string, unknown>;

// profile ----------------------------------------------------------------------

Deno.test("profile GET returns the caller's profile", async () => {
  const store = new MemoryProfiles();
  store.rows.set(alice.id, { displayName: "Alice", createdAt: "2026-10-01T08:00:01.000Z" });
  const h = withHttp((r) => handleProfile(r, fakeAuth(alice), () => store));
  const res = await h(req("GET", "profile", undefined, auth));
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("access-control-allow-origin"), "*");
  assertEquals(await res.json(), {
    id: alice.id,
    email: alice.email,
    displayName: "Alice",
    createdAt: alice.createdAt,
    providers: ["email"],
    hasPassword: true,
  });
});

Deno.test("profile GET for a social account: hasPassword false, no row → null name", async () => {
  const h = withHttp((r) => handleProfile(r, fakeAuth(googler), () => new MemoryProfiles()));
  const body = json(await (await h(req("GET", "profile", undefined, auth))).json());
  assertEquals(body.providers, ["google"]);
  assertEquals(body.hasPassword, false);
  assertEquals(body.displayName, null);
});

Deno.test("profile requires a valid token", async () => {
  const h = withHttp((r) => handleProfile(r, fakeAuth(alice), () => new MemoryProfiles()));
  let res = await h(req("GET", "profile"));
  assertEquals(res.status, 401);
  assertEquals(json(await res.json()).error, {
    code: "unauthorized",
    message: "Missing, invalid or expired token",
  });
  res = await h(req("PUT", "profile", { displayName: "X" }, { authorization: "Bearer bad" }));
  assertEquals(res.status, 401);
});

Deno.test("profile PUT trims and stores the name", async () => {
  const store = new MemoryProfiles();
  const h = withHttp((r) => handleProfile(r, fakeAuth(alice), () => store));
  const res = await h(req("PUT", "profile", { displayName: "  Quest Hero  " }, auth));
  assertEquals(res.status, 200);
  assertEquals(json(await res.json()).displayName, "Quest Hero");
  assertEquals(store.rows.get(alice.id)?.displayName, "Quest Hero");
});

Deno.test("profile PUT validates displayName (1–50 chars after trim)", async () => {
  const h = withHttp((r) => handleProfile(r, fakeAuth(alice), () => new MemoryProfiles()));
  for (
    const bad of [{}, { displayName: 3 }, { displayName: "   " }, { displayName: "x".repeat(51) }]
  ) {
    const res = await h(req("PUT", "profile", bad, auth));
    assertEquals(res.status, 400, JSON.stringify(bad));
    assertEquals(json(json(await res.json()).error).code, "invalid_input");
  }
  assertEquals((await h(req("PUT", "profile", { displayName: "é".repeat(50) }, auth))).status, 200);
  assertEquals((await h(req("PUT", "profile", "nope", auth))).status, 400);
});

Deno.test("profile: other methods 405, sub-paths 404, OPTIONS 200", async () => {
  const h = withHttp((r) => handleProfile(r, fakeAuth(alice), () => new MemoryProfiles()));
  assertEquals((await h(req("POST", "profile", {}, auth))).status, 405);
  assertEquals((await h(req("GET", "profile/other-user", undefined, auth))).status, 404);
  assertEquals((await h(req("OPTIONS", "profile"))).status, 200);
});

Deno.test("validateDisplayName and providersOf", () => {
  assertEquals(validateDisplayName({ displayName: " a " }), "a");
  assertEquals(
    providersOf([{ provider: "email" }, { provider: "google" }, { provider: "email" }], [
      "email",
      "apple",
    ]),
    ["email", "google", "apple"],
  );
  assertEquals(providersOf(null), []);
});

// auth-change-password ------------------------------------------------------------

function fakePasswords(current = "old-secret") {
  const calls: string[] = [];
  let password = current;
  let verified = false;
  const gw: PasswordGateway = {
    verify(email, pw) {
      calls.push(`verify:${email}`);
      verified = pw === password;
      return Promise.resolve({
        error: verified ? null : { status: 400, code: "invalid_credentials" },
      });
    },
    update(newPassword) {
      calls.push("update");
      if (!verified) return Promise.resolve({ error: { status: 401, code: "no_session" } });
      password = newPassword;
      return Promise.resolve({ error: null });
    },
  };
  return {
    gw,
    calls,
    get password() {
      return password;
    },
  };
}

const change = (user: AccountUser, gw: PasswordGateway) =>
  withHttp((r) => handleChangePassword(r, fakeAuth(user), gw));

Deno.test("change password: correct current password → 204 and updated", async () => {
  const p = fakePasswords();
  const res = await change(alice, p.gw)(
    req("POST", "auth-change-password", {
      currentPassword: "old-secret",
      newPassword: "new-secret",
    }, auth),
  );
  assertEquals(res.status, 204);
  assertEquals(await res.text(), "");
  assertEquals(p.calls, ["verify:alice@example.com", "update"]);
  assertEquals(p.password, "new-secret");
});

Deno.test("change password: wrong current password → 401 invalid_credentials", async () => {
  const p = fakePasswords();
  const res = await change(alice, p.gw)(
    req(
      "POST",
      "auth-change-password",
      { currentPassword: "nope", newPassword: "new-secret" },
      auth,
    ),
  );
  assertEquals(res.status, 401);
  assertEquals(json(json(await res.json()).error).code, "invalid_credentials");
  assertEquals(p.calls, ["verify:alice@example.com"]);
  assertEquals(p.password, "old-secret");
});

Deno.test("change password: weak or same password → 400 before verifying", async () => {
  const p = fakePasswords();
  const h = change(alice, p.gw);
  let res = await h(
    req(
      "POST",
      "auth-change-password",
      { currentPassword: "old-secret", newPassword: "12345" },
      auth,
    ),
  );
  assertEquals(res.status, 400);
  assertEquals(json(json(await res.json()).error).code, "weak_password");
  res = await h(
    req(
      "POST",
      "auth-change-password",
      { currentPassword: "x", newPassword: "y".repeat(73) },
      auth,
    ),
  );
  assertEquals(json(json(await res.json()).error).code, "weak_password");
  res = await h(
    req("POST", "auth-change-password", {
      currentPassword: "old-secret",
      newPassword: "old-secret",
    }, auth),
  );
  assertEquals(res.status, 400);
  assertEquals(json(json(await res.json()).error).code, "same_password");
  assertEquals(p.calls, []);
});

Deno.test("change password: social account → 409 no_password", async () => {
  const p = fakePasswords();
  const res = await change(googler, p.gw)(
    req("POST", "auth-change-password", { currentPassword: "a", newPassword: "new-secret" }, auth),
  );
  assertEquals(res.status, 409);
  assertEquals(json(json(await res.json()).error).code, "no_password");
  assertEquals(p.calls, []);
});

Deno.test("change password: auth, body validation and method", async () => {
  const p = fakePasswords();
  const h = change(alice, p.gw);
  assertEquals(
    (await h(req("POST", "auth-change-password", { currentPassword: "a", newPassword: "bbbbbb" })))
      .status,
    401,
  );
  assertEquals(
    (await h(req("POST", "auth-change-password", { newPassword: "bbbbbb" }, auth))).status,
    400,
  );
  assertEquals(
    (await h(req("POST", "auth-change-password", { currentPassword: "a" }, auth))).status,
    400,
  );
  assertEquals((await h(req("GET", "auth-change-password", undefined, auth))).status, 405);
});

Deno.test("change password: Supabase update errors are mapped", async () => {
  const gw = (error: { status?: number; code?: string }): PasswordGateway => ({
    verify: () => Promise.resolve({ error: null }),
    update: () => Promise.resolve({ error }),
  });
  const body = { currentPassword: "old-secret", newPassword: "new-secret" };
  let res = await change(alice, gw({ status: 422, code: "weak_password" }))(
    req("POST", "auth-change-password", body, auth),
  );
  assertEquals(json(json(await res.json()).error).code, "weak_password");
  res = await change(alice, gw({ status: 422, code: "same_password" }))(
    req("POST", "auth-change-password", body, auth),
  );
  assertEquals(json(json(await res.json()).error).code, "same_password");
  res = await change(alice, gw({ status: 500 }))(req("POST", "auth-change-password", body, auth));
  assertEquals(res.status, 500);
});

// account-delete --------------------------------------------------------------------

function fakeDeleter() {
  const calls: string[] = [];
  const d: AccountDeleter = {
    deleteData(id) {
      calls.push(`data:${id}`);
      return Promise.resolve();
    },
    deleteAuthUser(id) {
      calls.push(`auth:${id}`);
      return Promise.resolve();
    },
  };
  return { d, calls };
}

Deno.test("account-delete: confirm DELETE → data then auth user deleted, 204", async () => {
  const { d, calls } = fakeDeleter();
  const h = withHttp((r) => handleAccountDelete(r, fakeAuth(alice), () => d));
  const res = await h(req("POST", "account-delete", { confirm: "DELETE" }, auth));
  assertEquals(res.status, 204);
  assertEquals(calls, ["data:user-alice", "auth:user-alice"]);
});

Deno.test("account-delete: the id comes from the token, never the body", async () => {
  const { d, calls } = fakeDeleter();
  const h = withHttp((r) => handleAccountDelete(r, fakeAuth(alice), () => d));
  const res = await h(
    req("POST", "account-delete", { confirm: "DELETE", userId: "victim", id: "victim" }, auth),
  );
  assertEquals(res.status, 204);
  assertEquals(calls, ["data:user-alice", "auth:user-alice"]);
});

Deno.test("account-delete: missing or wrong confirm → 400, nothing deleted", async () => {
  const { d, calls } = fakeDeleter();
  const h = withHttp((r) => handleAccountDelete(r, fakeAuth(alice), () => d));
  for (const body of [{}, { confirm: "delete" }, { confirm: true }, { confirm: " DELETE" }]) {
    const res = await h(req("POST", "account-delete", body, auth));
    assertEquals(res.status, 400, JSON.stringify(body));
    assertEquals(json(json(await res.json()).error).code, "invalid_input");
  }
  assertEquals((await h(req("POST", "account-delete", undefined, auth))).status, 400);
  assertEquals(calls, []);
});

Deno.test("account-delete: token required, POST only", async () => {
  const { d, calls } = fakeDeleter();
  const a = fakeAuth(alice);
  const h = withHttp((r) => handleAccountDelete(r, a, () => d));
  assertEquals((await h(req("POST", "account-delete", { confirm: "DELETE" }))).status, 401);
  assertEquals(
    (await h(req("POST", "account-delete", { confirm: "DELETE" }, { authorization: "Bearer x" })))
      .status,
    401,
  );
  assertEquals((await h(req("DELETE", "account-delete", undefined, auth))).status, 405);
  assertEquals(calls, []);
});

Deno.test("account-delete: a failing step surfaces as an error response", async () => {
  const d: AccountDeleter = {
    deleteData: () => Promise.resolve(),
    deleteAuthUser: () => Promise.reject(new Error("boom")),
  };
  const h = withHttp((r) => handleAccountDelete(r, fakeAuth(alice), () => d));
  const res = await h(req("POST", "account-delete", { confirm: "DELETE" }, auth));
  assertEquals(res.status, 500);
  assertEquals(json(json(await res.json()).error).code, "internal_error");
});
