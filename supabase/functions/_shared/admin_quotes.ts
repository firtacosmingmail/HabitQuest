/**
 * `admin-quotes`: the admin console's view of the quotes (see supabase/API.md).
 *
 * Unlike the public `GET /quotes`, it lists every quote (past, today,
 * scheduled for the future and unscheduled) with its love count, and it can
 * delete one. Create, edit and reschedule stay on `POST`/`PUT /quotes`;
 * unscheduling is `PUT /quotes?id=` with `{"day": null}`.
 *
 * Storage sits behind [AdminQuoteStore] so the routing, validation and admin
 * check are unit-tested with fakes (tests/admin_test.ts).
 */
import { type AdminCaller, requireAdmin } from "./admin.ts";
import { invalidInput, json, methodNotAllowed, noContent, notFound } from "./errors.ts";
import { subPath } from "./http.ts";
import type { Quote } from "./quotes.ts";
import { parseDateParam, requireUuid } from "./validation.ts";

/** A quote in the admin listing: plus how many users love it. */
export interface AdminQuote extends Quote {
  loves: number;
}

export type ScheduledFilter = "all" | "scheduled" | "unscheduled";

export interface QuoteSearch {
  /** Case-insensitive substring of text or author; null = any. */
  query: string | null;
  /** Inclusive day range; either bound set → scheduled quotes only. */
  from: string | null;
  to: string | null;
  scheduled: ScheduledFilter;
  limit: number;
  offset: number;
}

export interface QuotePage {
  total: number;
  items: AdminQuote[];
}

/** Service-role access to quotes, used only after the admin check. */
export interface AdminQuoteStore {
  /** Ordered: unscheduled first, then day desc, then createdAt desc, then id. */
  search(s: QuoteSearch): Promise<QuotePage>;
  /** False when the id does not exist. Loves cascade. */
  delete(id: string): Promise<boolean>;
}

export interface AdminQuotesDeps<C extends AdminCaller = AdminCaller> {
  authenticate(req: Request): Promise<C>;
  store(caller: C): AdminQuoteStore;
  admins(): string[];
}

export const DEFAULT_PAGE = 100;
export const MAX_PAGE = 500;
export const MAX_QUERY_LENGTH = 200;

function intParam(raw: string | null, field: string, min: number, max: number, def: number) {
  if (raw === null || raw === "") return def;
  if (!/^\d+$/.test(raw) || Number(raw) < min || Number(raw) > max) {
    throw invalidInput(`${field} must be an integer from ${min} to ${max}`);
  }
  return Number(raw);
}

/** Validates the GET /admin-quotes query string. */
export function parseQuoteSearch(params: URLSearchParams): QuoteSearch {
  const q = params.get("q")?.trim() ?? "";
  if ([...q].length > MAX_QUERY_LENGTH) {
    throw invalidInput(`q must be at most ${MAX_QUERY_LENGTH} characters`);
  }
  const from = parseDateParam(params.get("from"), "from");
  const to = parseDateParam(params.get("to"), "to");
  if (from !== null && to !== null && from > to) throw invalidInput("from must not be after to");
  const scheduled = params.get("scheduled") ?? "all";
  if (!["all", "scheduled", "unscheduled"].includes(scheduled)) {
    throw invalidInput("scheduled must be all, scheduled or unscheduled");
  }
  if (scheduled === "unscheduled" && (from !== null || to !== null)) {
    throw invalidInput("A date range only matches scheduled quotes");
  }
  return {
    query: q === "" ? null : q,
    from,
    to,
    scheduled: scheduled as ScheduledFilter,
    limit: intParam(params.get("limit"), "limit", 1, MAX_PAGE, DEFAULT_PAGE),
    offset: intParam(params.get("offset"), "offset", 0, 1_000_000, 0),
  };
}

export async function handleAdminQuotes<C extends AdminCaller>(
  req: Request,
  deps: AdminQuotesDeps<C>,
): Promise<Response> {
  const url = new URL(req.url);
  if (subPath(url, "admin-quotes").length !== 0) throw notFound(`Unknown route ${url.pathname}`);
  const method = req.method.toUpperCase();
  if (!["GET", "DELETE"].includes(method)) throw methodNotAllowed(method);

  const caller = await deps.authenticate(req);
  requireAdmin(caller, deps.admins(), "Only admins can manage quotes");
  const store = deps.store(caller);

  if (method === "GET") {
    const search = parseQuoteSearch(url.searchParams);
    const page = await store.search(search);
    return json({
      total: page.total,
      limit: search.limit,
      offset: search.offset,
      items: page.items,
    });
  }

  const id = requireUuid(url.searchParams.get("id"), "id");
  if (!(await store.delete(id))) throw notFound(`No quote with id ${id}`);
  return noContent();
}
