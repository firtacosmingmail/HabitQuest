/**
 * Last-write-wins decision. Mirrors the SQL functions in
 * supabase/migrations/*_lww_functions.sql (`where stored.updated_at <
 * excluded.updated_at`): a write is applied only if nothing is stored or the
 * incoming updatedAt is strictly newer. Equal timestamps are a no-op, which
 * makes retries idempotent.
 */
import { timestampMillis } from "./validation.ts";

export function shouldApply(
  incomingUpdatedAt: string,
  stored: { updatedAt: string } | null | undefined,
): boolean {
  if (!stored) return true;
  return timestampMillis(incomingUpdatedAt) > timestampMillis(stored.updatedAt);
}

/** A soft delete is a write of a tombstone with the given time. */
export function tombstone<T extends { updatedAt: string; deletedAt: string | null }>(
  stored: T,
  at: string,
): T {
  return { ...stored, updatedAt: at, deletedAt: at };
}
