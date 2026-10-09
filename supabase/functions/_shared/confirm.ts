/**
 * Email confirmation link handler (auth-confirm).
 *
 * The confirmation email links here with ?token_hash=...&type=...; we verify
 * the OTP with Supabase Auth and 303-redirect to a static success or error
 * page (Edge Functions can't serve HTML). See README "Email confirmation".
 */
import { corsHeaders } from "./cors.ts";

export const OTP_TYPES = ["signup", "email", "email_change", "recovery", "invite"] as const;
export type ConfirmOtpType = typeof OTP_TYPES[number];

export interface VerifyOtpError {
  code?: string;
  status?: number;
  message?: string;
}

/** Verifies a token hash; resolves with an error or null on success. */
export type VerifyOtp = (
  tokenHash: string,
  type: ConfirmOtpType,
) => Promise<{ error: VerifyOtpError | null }>;

export interface ConfirmConfig {
  successUrl?: string;
  errorUrl?: string;
}

export type ConfirmReason = "expired" | "invalid" | "missing";

/** Maps a Supabase verifyOtp error to the error page's reason. */
export function reasonFor(error: VerifyOtpError): ConfirmReason {
  return (error.code ?? "").toLowerCase() === "otp_expired" ? "expired" : "invalid";
}

function redirect(location: string): Response {
  return new Response(null, {
    status: 303,
    headers: { ...corsHeaders, location, "cache-control": "no-store" },
  });
}

function text(status: number, body: string, extra: Record<string, string> = {}): Response {
  return new Response(body, {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-store",
      ...extra,
    },
  });
}

function errorResponse(cfg: ConfirmConfig, reason: ConfirmReason): Response {
  if (!cfg.errorUrl) {
    const msg = reason === "expired"
      ? "This confirmation link has expired."
      : reason === "missing"
      ? "This confirmation link is incomplete."
      : "This confirmation link is invalid.";
    return text(400, `${msg} Please sign up again or request a new link from Habit Quest.`);
  }
  const url = new URL(cfg.errorUrl);
  url.searchParams.set("reason", reason);
  return redirect(url.toString());
}

function successResponse(cfg: ConfirmConfig): Response {
  if (!cfg.successUrl) {
    return text(200, "Email confirmed! Go back to Habit Quest and log in.");
  }
  return redirect(cfg.successUrl);
}

export async function handleConfirm(
  req: Request,
  verifyOtp: VerifyOtp,
  cfg: ConfirmConfig,
): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { status: 200, headers: corsHeaders });
  if (req.method !== "GET" && req.method !== "HEAD") {
    return text(405, "Method not allowed", { allow: "GET, HEAD, OPTIONS" });
  }
  const params = new URL(req.url).searchParams;
  const tokenHash = params.get("token_hash")?.trim();
  if (!tokenHash) return errorResponse(cfg, "missing");
  const rawType = params.get("type")?.trim() || "signup";
  if (!(OTP_TYPES as readonly string[]).includes(rawType)) return errorResponse(cfg, "invalid");
  let error: VerifyOtpError | null;
  try {
    ({ error } = await verifyOtp(tokenHash, rawType as ConfirmOtpType));
  } catch (e) {
    console.error("verifyOtp threw", e);
    error = { message: "verify failed" };
  }
  if (error) return errorResponse(cfg, reasonFor(error));
  return successResponse(cfg);
}

/** Reads the redirect targets from function secrets. */
export function readConfirmConfig(): ConfirmConfig {
  return {
    successUrl: Deno.env.get("CONFIRM_SUCCESS_URL") || undefined,
    errorUrl: Deno.env.get("CONFIRM_ERROR_URL") || undefined,
  };
}
