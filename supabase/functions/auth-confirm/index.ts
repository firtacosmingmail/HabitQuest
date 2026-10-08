// GET auth-confirm?token_hash=...&type=signup → 303 to the success/error page
// (see supabase/API.md and README "Email confirmation")
import { handleConfirm, readConfirmConfig } from "../_shared/confirm.ts";
import { anonClient, readEnv } from "../_shared/supabase.ts";

Deno.serve((req) =>
  handleConfirm(
    req,
    async (tokenHash, type) => {
      const { error } = await anonClient(readEnv(req)).auth.verifyOtp({
        token_hash: tokenHash,
        type,
      });
      return {
        error: error ? { code: error.code, status: error.status, message: error.message } : null,
      };
    },
    readConfirmConfig(),
  )
);
