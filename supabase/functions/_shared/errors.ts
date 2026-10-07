import { corsHeaders } from "./cors.ts";

/** An error that maps to a contract error response. */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export const invalidInput = (message: string) => new ApiError(400, "invalid_input", message);
export const unauthorized = (message = "Missing, invalid or expired token") =>
  new ApiError(401, "unauthorized", message);
export const notFound = (message = "Not found") => new ApiError(404, "not_found", message);
export const methodNotAllowed = (method: string) =>
  new ApiError(405, "method_not_allowed", `Method ${method} not allowed`);

/** JSON response with CORS headers. */
export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

/** Empty response (e.g. 204) with CORS headers. */
export function noContent(status = 204): Response {
  return new Response(null, { status, headers: corsHeaders });
}

/** Contract error body: {"error":{"code","message"}}. */
export function errorResponse(status: number, code: string, message: string) {
  return json({ error: { code, message } }, status);
}

/** Converts anything thrown by a handler into a contract error response. */
export function toErrorResponse(err: unknown): Response {
  if (err instanceof ApiError) {
    return errorResponse(err.status, err.code, err.message);
  }
  console.error("unhandled error", err);
  return errorResponse(500, "internal_error", "Internal server error");
}

/** Shape of errors returned by PostgREST / supabase-js. */
export interface DbError {
  code?: string;
  message?: string;
  details?: string | null;
  hint?: string | null;
}

/** Maps a database error to an ApiError. */
export function mapDbError(err: DbError): ApiError {
  const code = err.code ?? "";
  const message = err.message ?? "Database error";
  switch (code) {
    case "23503": // foreign_key_violation (check-in for an unknown habit)
      return new ApiError(
        409,
        "habit_not_found",
        "The habit of this check-in does not exist on the server; push the habit first",
      );
    case "23514": // check_violation
    case "23502": // not_null_violation
    case "22P02": // invalid_text_representation
    case "22007": // invalid_datetime_format
    case "22008": // datetime_field_overflow
    case "22003": // numeric_value_out_of_range
    case "22023": // invalid_parameter_value
      return invalidInput(message);
    case "42501": // insufficient_privilege (RLS / not signed in)
    case "PGRST301": // JWT invalid
    case "PGRST302":
      return unauthorized();
    default:
      console.error("database error", err);
      return new ApiError(500, "internal_error", "Database error");
  }
}
