/**
 * Account endpoints: `profile` (GET/PUT), `auth-change-password` (POST) and
 * `account-delete` (POST). Supabase sits behind small interfaces so the
 * request handling is unit-tested with fakes (tests/account_test.ts);
 * supabase_account.ts holds the real implementations.
 *
 * The caller is always identified by their verified access token (never by
 * anything in the body), so a user can only read, change or delete
 * themselves.
 */
import { ApiError, invalidInput, json, methodNotAllowed, noContent, notFound } from "./errors.ts";
import { readJsonObject, subPath } from "./http.ts";
import type { AuthErrorLike } from "./auth.ts";
import { isPlainObject } from "./validation.ts";

/** The verified caller (from auth.getUser with their own token). */
export interface AccountUser {
  id: string;
  email: string | null;
  createdAt: string;
  /** Sign-in providers from the user's identities, e.g. ["email", "google"]. */
  providers: string[];
}

export interface CallerContext {
  user: AccountUser;
  token: string;
}

/** Validates the bearer token (throws 401) and returns the caller. */
export type Authenticate<C extends CallerContext = CallerContext> = (req: Request) => Promise<C>;

export interface ProfileRow {
  displayName: string | null;
  createdAt: string | null;
}

/** The caller's `profiles` row, accessed with their JWT (RLS applies). */
export interface ProfileStore {
  get(userId: string): Promise<ProfileRow | null>;
  /** Updates (or creates) the row; returns the stored row. */
  setDisplayName(userId: string, displayName: string): Promise<ProfileRow>;
}

/**
 * One password change (create a new gateway per request): [verify] signs in
 * with email + current password on a separate anon client, and [update]
 * then calls auth.updateUser with the session that sign-in returned.
 */
export interface PasswordGateway {
  verify(email: string, password: string): Promise<{ error: AuthErrorLike | null }>;
  update(newPassword: string): Promise<{ error: AuthErrorLike | null }>;
}

export interface AccountDeleter {
  /** Deletes the caller's rows (check_ins, habits, game_state, profiles) via RLS. */
  deleteData(userId: string): Promise<void>;
  /** auth.admin.deleteUser with the service-role client (server-side only). */
  deleteAuthUser(userId: string): Promise<void>;
}

export const DISPLAY_NAME_MAX = 50;
export const PASSWORD_MIN = 6;
export const PASSWORD_MAX = 72;
export const DELETE_CONFIRMATION = "DELETE";

/** Unique, sorted-by-first-seen provider names. */
export function providersOf(
  identities: { provider?: string | null }[] | null | undefined,
  appProviders?: unknown,
): string[] {
  const out: string[] = [];
  const add = (p: unknown) => {
    if (typeof p === "string" && p !== "" && !out.includes(p)) out.push(p);
  };
  for (const i of identities ?? []) add(i.provider);
  if (Array.isArray(appProviders)) appProviders.forEach(add);
  return out;
}

/** A password can be changed only for accounts with an email identity. */
export const hasPassword = (u: AccountUser) => u.providers.includes("email");

function profileJson(u: AccountUser, row: ProfileRow | null) {
  return {
    id: u.id,
    email: u.email,
    displayName: row?.displayName ?? null,
    createdAt: u.createdAt || row?.createdAt || null,
    providers: u.providers,
    hasPassword: hasPassword(u),
  };
}

/** Validates `{displayName}`: a string, trimmed, 1–50 characters. */
export function validateDisplayName(body: Record<string, unknown>): string {
  const v = body.displayName;
  if (typeof v !== "string") throw invalidInput("displayName must be a string");
  const name = v.trim();
  const len = [...name].length;
  if (len < 1) throw invalidInput("displayName must not be empty");
  if (len > DISPLAY_NAME_MAX) {
    throw invalidInput(`displayName must be at most ${DISPLAY_NAME_MAX} characters`);
  }
  return name;
}

function ensureNoSubPath(req: Request, name: string) {
  const url = new URL(req.url);
  if (subPath(url, name).length > 0) throw notFound(`Unknown route ${url.pathname}`);
}

export async function handleProfile<C extends CallerContext>(
  req: Request,
  authenticate: Authenticate<C>,
  store: (ctx: C) => ProfileStore,
): Promise<Response> {
  ensureNoSubPath(req, "profile");
  const method = req.method.toUpperCase();
  if (method !== "GET" && method !== "PUT") throw methodNotAllowed(method);
  const ctx = await authenticate(req);
  const profiles = store(ctx);
  if (method === "GET") {
    return json(profileJson(ctx.user, await profiles.get(ctx.user.id)));
  }
  const displayName = validateDisplayName(await readJsonObject(req));
  return json(profileJson(ctx.user, await profiles.setDisplayName(ctx.user.id, displayName)));
}

interface PasswordChange {
  currentPassword: string;
  newPassword: string;
}

function validatePasswordChange(body: Record<string, unknown>): PasswordChange {
  const { currentPassword, newPassword } = body;
  if (typeof currentPassword !== "string" || currentPassword.length === 0) {
    throw invalidInput("currentPassword is required");
  }
  if (typeof newPassword !== "string" || newPassword.length === 0) {
    throw invalidInput("newPassword is required");
  }
  return { currentPassword, newPassword };
}

/** The project's password rules (config.toml: minimum_password_length = 6). */
export function checkPasswordStrength(password: string, current: string) {
  if (password.length < PASSWORD_MIN) {
    throw new ApiError(
      400,
      "weak_password",
      `Password should be at least ${PASSWORD_MIN} characters`,
    );
  }
  if (password.length > PASSWORD_MAX) {
    throw new ApiError(
      400,
      "weak_password",
      `Password must be at most ${PASSWORD_MAX} characters`,
    );
  }
  if (password === current) {
    throw new ApiError(400, "same_password", "The new password must differ from the current one");
  }
}

function mapPasswordUpdateError(err: AuthErrorLike): ApiError {
  const status = err.status ?? 500;
  if (status === 429 || err.code === "over_request_rate_limit") {
    return new ApiError(429, "rate_limited", "Too many requests, try again later");
  }
  if (err.code === "weak_password") {
    return new ApiError(400, "weak_password", err.message ?? "Password is too weak");
  }
  if (err.code === "same_password") {
    return new ApiError(400, "same_password", "The new password must differ from the current one");
  }
  console.error("password update failed", { status, code: err.code });
  return new ApiError(500, "internal_error", "Could not change the password");
}

export async function handleChangePassword<C extends CallerContext>(
  req: Request,
  authenticate: Authenticate<C>,
  passwords: PasswordGateway,
): Promise<Response> {
  ensureNoSubPath(req, "auth-change-password");
  const method = req.method.toUpperCase();
  if (method !== "POST") throw methodNotAllowed(method);
  const { user } = await authenticate(req);
  const input = validatePasswordChange(await readJsonObject(req));
  if (!hasPassword(user) || !user.email) {
    throw new ApiError(409, "no_password", "This account signs in without a password");
  }
  checkPasswordStrength(input.newPassword, input.currentPassword);

  const verified = await passwords.verify(user.email, input.currentPassword);
  if (verified.error) {
    const status = verified.error.status ?? 500;
    if (status === 429) throw new ApiError(429, "rate_limited", "Too many attempts, try later");
    if (status >= 500) throw new ApiError(500, "internal_error", "Auth service error");
    throw new ApiError(401, "invalid_credentials", "The current password is not correct");
  }
  const updated = await passwords.update(input.newPassword);
  if (updated.error) throw mapPasswordUpdateError(updated.error);
  return noContent();
}

export async function handleAccountDelete<C extends CallerContext>(
  req: Request,
  authenticate: Authenticate<C>,
  deleter: (ctx: C) => AccountDeleter,
): Promise<Response> {
  ensureNoSubPath(req, "account-delete");
  const method = req.method.toUpperCase();
  if (method !== "POST") throw methodNotAllowed(method);
  const ctx = await authenticate(req);
  const body = await readJsonObject(req);
  if (!isPlainObject(body) || body.confirm !== DELETE_CONFIRMATION) {
    throw invalidInput(`Send {"confirm":"${DELETE_CONFIRMATION}"} to delete the account`);
  }
  // The id comes from the verified token only.
  const d = deleter(ctx);
  await d.deleteData(ctx.user.id);
  await d.deleteAuthUser(ctx.user.id);
  return noContent();
}
