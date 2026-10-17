/**
 * The one admin check shared by every admin-only endpoint (`quotes` POST/PUT,
 * `admin-quotes`, `admin-stats`).
 *
 * An admin is the service role (bearer = SUPABASE_SERVICE_ROLE_KEY, compared
 * in constant time by the caller's authenticate function) or a signed-in user
 * whose email is listed in the QUOTE_ADMINS function secret (comma, semicolon
 * or whitespace separated, case-insensitive). The secret keeps its historical
 * name so existing deployments need no change.
 */
import { forbidden } from "./errors.ts";

/** A verified caller, as far as the admin check is concerned. */
export interface AdminCaller {
  /** null for the service role. */
  userId: string | null;
  email: string | null;
  serviceRole: boolean;
}

/** Name of the function secret listing the admin emails. */
export const ADMINS_SECRET = "QUOTE_ADMINS";

/** Parses QUOTE_ADMINS: comma/semicolon/whitespace separated emails, lower-cased. */
export function parseAdmins(raw: string | undefined | null): string[] {
  return (raw ?? "").split(/[\s,;]+/).map((s) => s.trim().toLowerCase()).filter((s) => s !== "");
}

/** Service role, or an email in [admins] (case-insensitive). */
export function isAdmin(caller: AdminCaller, admins: string[]): boolean {
  if (caller.serviceRole) return true;
  const email = caller.email?.trim().toLowerCase();
  if (!email) return false;
  return admins.some((a) => a.trim().toLowerCase() === email);
}

/** Throws 403 forbidden unless [caller] is an admin. */
export function requireAdmin(
  caller: AdminCaller,
  admins: string[],
  message = "Admins only",
): void {
  if (!isAdmin(caller, admins)) throw forbidden(message);
}

/** The admin emails from the function environment (QUOTE_ADMINS). */
export function envAdmins(): string[] {
  return parseAdmins(Deno.env.get(ADMINS_SECRET));
}
