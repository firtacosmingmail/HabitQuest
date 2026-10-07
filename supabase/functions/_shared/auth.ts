/**
 * Auth endpoints (register/login/refresh/logout). Supabase Auth sits behind
 * [AuthGateway] so the request handling and error mapping are unit-tested
 * with a fake (tests/auth_test.ts); supabase_auth.ts is the real gateway.
 */
import {
  ApiError,
  invalidInput,
  json,
  methodNotAllowed,
  noContent,
  unauthorized,
} from "./errors.ts";
import { readJsonObject } from "./http.ts";
import { type AuthSessionLike, toSession } from "./mapping.ts";
import { validateCredentials, validateRefresh, validateRegistration } from "./validation.ts";

/** Subset of Supabase Auth's error (AuthApiError). */
export interface AuthErrorLike {
  status?: number;
  code?: string;
  message?: string;
}

export interface SignUpResult {
  session: AuthSessionLike | null;
  user: { id: string; identities?: unknown[] | null } | null;
}

export type AuthResult<T> = { data: T; error: null } | {
  data: null;
  error: AuthErrorLike;
};

export interface AuthGateway {
  signUp(
    email: string,
    password: string,
    displayName: string | null,
  ): Promise<AuthResult<SignUpResult>>;
  signIn(email: string, password: string): Promise<AuthResult<AuthSessionLike>>;
  refresh(refreshToken: string): Promise<AuthResult<AuthSessionLike>>;
  signOut(accessToken: string): Promise<{ error: AuthErrorLike | null }>;
}

export type AuthOperation = "register" | "login" | "refresh" | "logout";

const RATE_LIMIT_CODES = new Set([
  "over_request_rate_limit",
  "over_email_send_rate_limit",
  "over_sms_send_rate_limit",
]);

/** Maps a Supabase Auth error to a contract error for the given operation. */
export function mapAuthError(op: AuthOperation, err: AuthErrorLike): ApiError {
  const status = err.status ?? 500;
  const code = err.code ?? "";
  const message = err.message ?? "Auth error";

  if (status === 429 || RATE_LIMIT_CODES.has(code)) {
    return new ApiError(429, "rate_limited", "Too many requests, try again later");
  }
  if (status >= 500) {
    console.error(`auth ${op} failed`, err);
    return new ApiError(500, "internal_error", "Auth service error");
  }

  switch (op) {
    case "register":
      if (
        code === "user_already_exists" || code === "email_exists" ||
        status === 422 && /already registered/i.test(message)
      ) {
        return new ApiError(409, "email_taken", "An account with this email already exists");
      }
      if (code === "weak_password") {
        return new ApiError(400, "weak_password", message);
      }
      if (code === "signup_disabled") {
        return new ApiError(403, "signup_disabled", "Sign-ups are disabled");
      }
      return invalidInput(message);
    case "login":
      if (code === "email_not_confirmed") {
        return new ApiError(403, "email_not_confirmed", "Email address is not confirmed");
      }
      return new ApiError(401, "invalid_credentials", "Invalid email or password");
    case "refresh":
      return new ApiError(401, "invalid_refresh_token", "Refresh token is invalid or expired");
    case "logout":
      return unauthorized();
  }
}

function requirePost(req: Request) {
  if (req.method.toUpperCase() !== "POST") throw methodNotAllowed(req.method);
}

export async function handleRegister(req: Request, gw: AuthGateway): Promise<Response> {
  requirePost(req);
  const input = validateRegistration(await readJsonObject(req));
  const r = await gw.signUp(input.email, input.password, input.displayName);
  if (r.error) throw mapAuthError("register", r.error);
  if (r.data.session) return json({ session: toSession(r.data.session) });
  // With email confirmation on, Supabase hides existing accounts by returning
  // a user without identities instead of an error.
  const identities = r.data.user?.identities;
  if (r.data.user && Array.isArray(identities) && identities.length === 0) {
    throw new ApiError(409, "email_taken", "An account with this email already exists");
  }
  return json({ session: null, needsConfirmation: true });
}

export async function handleLogin(req: Request, gw: AuthGateway): Promise<Response> {
  requirePost(req);
  const input = validateCredentials(await readJsonObject(req));
  const r = await gw.signIn(input.email, input.password);
  if (r.error) throw mapAuthError("login", r.error);
  return json({ session: toSession(r.data) });
}

export async function handleRefresh(req: Request, gw: AuthGateway): Promise<Response> {
  requirePost(req);
  const token = validateRefresh(await readJsonObject(req));
  const r = await gw.refresh(token);
  if (r.error) throw mapAuthError("refresh", r.error);
  return json({ session: toSession(r.data) });
}

export async function handleLogout(
  req: Request,
  gw: AuthGateway,
  bearer: (req: Request) => string | null,
): Promise<Response> {
  requirePost(req);
  const token = bearer(req);
  if (!token) throw unauthorized("Missing bearer token");
  const { error } = await gw.signOut(token);
  // A session that is already gone counts as logged out.
  if (error && error.code !== "session_not_found") {
    throw mapAuthError("logout", error);
  }
  return noContent();
}
