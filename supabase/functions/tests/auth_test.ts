import { assertEquals } from "jsr:@std/assert@1";
import {
  type AuthErrorLike,
  type AuthGateway,
  type AuthResult,
  handleLogin,
  handleLogout,
  handleRefresh,
  handleRegister,
  mapAuthError,
  type SignUpResult,
} from "../_shared/auth.ts";
import { withHttp } from "../_shared/http.ts";
import type { AuthSessionLike } from "../_shared/mapping.ts";
import { bearerToken } from "../_shared/supabase.ts";
import { req } from "./fakes.ts";

const session: AuthSessionLike = {
  access_token: "at",
  refresh_token: "rt",
  expires_at: 1791364500,
  expires_in: 3600,
  user: { id: "u1", email: "a@b.co" },
};
const sessionJson = {
  accessToken: "at",
  refreshToken: "rt",
  expiresAt: 1791364500,
  user: { id: "u1", email: "a@b.co" },
};

const fail = (error: AuthErrorLike) => ({ data: null, error }) as const;

function gateway(over: Partial<AuthGateway> = {}): AuthGateway & { calls: unknown[][] } {
  const calls: unknown[][] = [];
  return {
    calls,
    signUp: (...a): Promise<AuthResult<SignUpResult>> => {
      calls.push(["signUp", ...a]);
      return Promise.resolve({
        data: { session, user: { id: "u1", identities: [{}] } },
        error: null,
      });
    },
    signIn: (...a) => {
      calls.push(["signIn", ...a]);
      return Promise.resolve({ data: session, error: null });
    },
    refresh: (...a) => {
      calls.push(["refresh", ...a]);
      return Promise.resolve({ data: session, error: null });
    },
    signOut: (...a) => {
      calls.push(["signOut", ...a]);
      return Promise.resolve({ error: null });
    },
    ...over,
  };
}

const run = (h: (r: Request, g: AuthGateway) => Promise<Response>, g: AuthGateway) =>
  withHttp((r) => h(r, g));

Deno.test("register → session; passes normalised email and display name", async () => {
  const g = gateway();
  const res = await run(handleRegister, g)(
    req("POST", "auth-register", { email: "A@B.co", password: "secret1", displayName: "Ann" }),
  );
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { session: sessionJson });
  assertEquals(g.calls[0], ["signUp", "a@b.co", "secret1", "Ann"]);
});

Deno.test("register without session → needsConfirmation", async () => {
  const g = gateway({
    signUp: () =>
      Promise.resolve({
        data: { session: null, user: { id: "u", identities: [{}] } },
        error: null,
      }),
  });
  const res = await run(handleRegister, g)(
    req("POST", "auth-register", { email: "a@b.co", password: "p" }),
  );
  assertEquals(await res.json(), { session: null, needsConfirmation: true });
});

Deno.test("register: existing email → 409 email_taken (error or obfuscated user)", async () => {
  for (
    const g of [
      gateway({
        signUp: () => Promise.resolve(fail({ status: 422, code: "user_already_exists" })),
      }),
      gateway({
        signUp: () =>
          Promise.resolve({
            data: { session: null, user: { id: "u", identities: [] } },
            error: null,
          }),
      }),
    ]
  ) {
    const res = await run(handleRegister, g)(
      req("POST", "auth-register", { email: "a@b.co", password: "p" }),
    );
    assertEquals(res.status, 409);
    assertEquals((await res.json()).error.code, "email_taken");
  }
});

Deno.test("register: weak password and invalid input", async () => {
  const g = gateway({
    signUp: () =>
      Promise.resolve(fail({ status: 422, code: "weak_password", message: "too short" })),
  });
  let res = await run(handleRegister, g)(
    req("POST", "auth-register", { email: "a@b.co", password: "p" }),
  );
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error.code, "weak_password");

  res = await run(handleRegister, gateway())(
    req("POST", "auth-register", { email: "bad", password: "p" }),
  );
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error.code, "invalid_input");

  res = await run(handleRegister, gateway())(req("GET", "auth-register"));
  assertEquals(res.status, 405);
});

Deno.test("login → session; bad credentials → 401 invalid_credentials", async () => {
  let res = await run(handleLogin, gateway())(
    req("POST", "auth-login", { email: "a@b.co", password: "p" }),
  );
  assertEquals(await res.json(), { session: sessionJson });

  const g = gateway({
    signIn: () => Promise.resolve(fail({ status: 400, code: "invalid_credentials" })),
  });
  res = await run(handleLogin, g)(req("POST", "auth-login", { email: "a@b.co", password: "p" }));
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error.code, "invalid_credentials");
});

Deno.test("refresh → session; bad token → 401 invalid_refresh_token", async () => {
  let res = await run(handleRefresh, gateway())(
    req("POST", "auth-refresh", { refreshToken: "rt" }),
  );
  assertEquals(await res.json(), { session: sessionJson });

  const g = gateway({
    refresh: () => Promise.resolve(fail({ status: 400, code: "refresh_token_not_found" })),
  });
  res = await run(handleRefresh, g)(req("POST", "auth-refresh", { refreshToken: "rt" }));
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error.code, "invalid_refresh_token");

  res = await run(handleRefresh, gateway())(req("POST", "auth-refresh", {}));
  assertEquals(res.status, 400);
});

Deno.test("logout: 204 with bearer, 401 without or when rejected", async () => {
  const logout = (g: AuthGateway) => withHttp((r) => handleLogout(r, g, bearerToken));
  const g = gateway();
  let res = await logout(g)(req("POST", "auth-logout", undefined, { authorization: "Bearer tok" }));
  assertEquals(res.status, 204);
  assertEquals(g.calls[0], ["signOut", "tok"]);

  res = await logout(gateway())(req("POST", "auth-logout"));
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error.code, "unauthorized");

  const bad = gateway({
    signOut: () => Promise.resolve({ error: { status: 401, code: "bad_jwt" } }),
  });
  res = await logout(bad)(req("POST", "auth-logout", undefined, { authorization: "Bearer x" }));
  assertEquals(res.status, 401);

  const gone = gateway({
    signOut: () => Promise.resolve({ error: { status: 404, code: "session_not_found" } }),
  });
  res = await logout(gone)(req("POST", "auth-logout", undefined, { authorization: "Bearer x" }));
  assertEquals(res.status, 204);
});

Deno.test("mapAuthError: rate limits and server errors", () => {
  assertEquals(mapAuthError("login", { status: 429 }).code, "rate_limited");
  assertEquals(
    mapAuthError("register", { status: 429, code: "over_email_send_rate_limit" }).status,
    429,
  );
  assertEquals(mapAuthError("refresh", { status: 503 }).code, "internal_error");
  assertEquals(mapAuthError("login", { status: 400, code: "email_not_confirmed" }).status, 403);
  assertEquals(mapAuthError("register", { status: 422, code: "email_exists" }).code, "email_taken");
});

Deno.test("bearerToken parsing", () => {
  const r = (v?: string) => new Request("http://x", { headers: v ? { authorization: v } : {} });
  assertEquals(bearerToken(r("Bearer abc")), "abc");
  assertEquals(bearerToken(r("bearer  abc ")), "abc");
  assertEquals(bearerToken(r("Basic abc")), null);
  assertEquals(bearerToken(r()), null);
});
