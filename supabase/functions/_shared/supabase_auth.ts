/** Real [AuthGateway] backed by supabase-js (anon key only). */
import type { AuthErrorLike, AuthGateway, AuthResult, SignUpResult } from "./auth.ts";
import type { AuthSessionLike } from "./mapping.ts";
import { anonClient, type Env } from "./supabase.ts";

const err = (e: { status?: number; code?: string; message?: string }): AuthErrorLike => ({
  status: e.status,
  code: e.code,
  message: e.message,
});

export function supabaseAuthGateway(env: Env): AuthGateway {
  const client = () => anonClient(env);
  return {
    async signUp(email, password, displayName): Promise<AuthResult<SignUpResult>> {
      const { data, error } = await client().auth.signUp({
        email,
        password,
        options: displayName ? { data: { display_name: displayName } } : undefined,
      });
      if (error) return { data: null, error: err(error) };
      return {
        data: {
          session: data.session as AuthSessionLike | null,
          user: data.user ? { id: data.user.id, identities: data.user.identities ?? null } : null,
        },
        error: null,
      };
    },
    async signIn(email, password) {
      const { data, error } = await client().auth.signInWithPassword({ email, password });
      if (error) return { data: null, error: err(error) };
      if (!data.session) {
        return { data: null, error: { status: 400, code: "invalid_credentials" } };
      }
      return { data: data.session as AuthSessionLike, error: null };
    },
    async refresh(refreshToken) {
      const { data, error } = await client().auth.refreshSession({
        refresh_token: refreshToken,
      });
      if (error) return { data: null, error: err(error) };
      if (!data.session) {
        return { data: null, error: { status: 400, code: "refresh_token_not_found" } };
      }
      return { data: data.session as AuthSessionLike, error: null };
    },
    async signOut(accessToken) {
      // POST /auth/v1/logout authenticated with the caller's own JWT (the
      // admin helper only needs the anon key for this call). Revokes the
      // refresh tokens of this session.
      const { error } = await client().auth.admin.signOut(accessToken, "local");
      return { error: error ? err(error) : null };
    },
  };
}
