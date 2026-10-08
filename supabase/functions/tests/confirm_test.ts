import { assertEquals } from "jsr:@std/assert@1";
import { handleConfirm, reasonFor, type VerifyOtp } from "../_shared/confirm.ts";

const cfg = {
  successUrl: "https://pages.example/hq/",
  errorUrl: "https://pages.example/hq/error.html",
};
const base = "https://x.supabase.co/functions/v1/auth-confirm";

function fake(error: { code?: string; message?: string } | null) {
  const calls: unknown[][] = [];
  const fn: VerifyOtp = (tokenHash, type) => {
    calls.push([tokenHash, type]);
    return Promise.resolve({ error });
  };
  return { fn, calls };
}

Deno.test("success redirects 303 to the success page", async () => {
  const v = fake(null);
  const res = await handleConfirm(new Request(`${base}?token_hash=abc&type=signup`), v.fn, cfg);
  assertEquals(res.status, 303);
  assertEquals(res.headers.get("location"), cfg.successUrl);
  assertEquals(v.calls, [["abc", "signup"]]);
});

Deno.test("type defaults to signup and other types pass through", async () => {
  const v = fake(null);
  await handleConfirm(new Request(`${base}?token_hash=abc`), v.fn, cfg);
  await handleConfirm(new Request(`${base}?token_hash=def&type=email_change`), v.fn, cfg);
  assertEquals(v.calls, [["abc", "signup"], ["def", "email_change"]]);
});

Deno.test("otp_expired redirects with reason=expired", async () => {
  const v = fake({ code: "otp_expired", message: "Email link is invalid or has expired" });
  const res = await handleConfirm(new Request(`${base}?token_hash=abc`), v.fn, cfg);
  assertEquals(res.status, 303);
  assertEquals(res.headers.get("location"), `${cfg.errorUrl}?reason=expired`);
});

Deno.test("other errors redirect with reason=invalid", async () => {
  const v = fake({ code: "validation_failed", message: "bad token" });
  const res = await handleConfirm(new Request(`${base}?token_hash=abc`), v.fn, cfg);
  assertEquals(res.status, 303);
  assertEquals(res.headers.get("location"), `${cfg.errorUrl}?reason=invalid`);
});

Deno.test("verifyOtp throwing redirects with reason=invalid", async () => {
  const fn: VerifyOtp = () => Promise.reject(new Error("network"));
  const res = await handleConfirm(new Request(`${base}?token_hash=abc`), fn, cfg);
  assertEquals(res.headers.get("location"), `${cfg.errorUrl}?reason=invalid`);
});

Deno.test("unknown type redirects with reason=invalid without calling verifyOtp", async () => {
  const v = fake(null);
  const res = await handleConfirm(new Request(`${base}?token_hash=abc&type=magic`), v.fn, cfg);
  assertEquals(res.headers.get("location"), `${cfg.errorUrl}?reason=invalid`);
  assertEquals(v.calls.length, 0);
});

Deno.test("missing token_hash redirects with reason=missing", async () => {
  const v = fake(null);
  const res = await handleConfirm(new Request(`${base}?type=signup&token_hash=`), v.fn, cfg);
  assertEquals(res.status, 303);
  assertEquals(res.headers.get("location"), `${cfg.errorUrl}?reason=missing`);
  assertEquals(v.calls.length, 0);
});

Deno.test("wrong method is 405, OPTIONS is a CORS preflight", async () => {
  const v = fake(null);
  const post = await handleConfirm(
    new Request(`${base}?token_hash=abc`, { method: "POST" }),
    v.fn,
    cfg,
  );
  assertEquals(post.status, 405);
  assertEquals(post.headers.get("allow"), "GET, HEAD, OPTIONS");
  await post.body?.cancel();
  const opt = await handleConfirm(new Request(base, { method: "OPTIONS" }), v.fn, cfg);
  assertEquals(opt.status, 200);
  assertEquals(opt.headers.get("access-control-allow-origin"), "*");
  await opt.body?.cancel();
  assertEquals(v.calls.length, 0);
});

Deno.test("falls back to plain text when the page URLs are unset", async () => {
  const ok = await handleConfirm(new Request(`${base}?token_hash=abc`), fake(null).fn, {});
  assertEquals(ok.status, 200);
  assertEquals(await ok.text(), "Email confirmed! Go back to Habit Quest and log in.");
  const bad = await handleConfirm(
    new Request(`${base}?token_hash=abc`),
    fake({ code: "otp_expired" }).fn,
    {},
  );
  assertEquals(bad.status, 400);
  assertEquals((await bad.text()).startsWith("This confirmation link has expired."), true);
});

Deno.test("reasonFor maps errors", () => {
  assertEquals(reasonFor({ code: "otp_expired" }), "expired");
  assertEquals(reasonFor({ code: "OTP_EXPIRED" }), "expired");
  assertEquals(reasonFor({ code: "bad_jwt" }), "invalid");
  assertEquals(reasonFor({}), "invalid");
});
