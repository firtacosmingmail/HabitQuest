import { preflight } from "./cors.ts";
import { invalidInput, toErrorResponse } from "./errors.ts";

export type Handler = (req: Request) => Promise<Response> | Response;

/**
 * Wraps a handler: answers OPTIONS preflight and turns thrown errors into
 * contract error responses.
 */
export function withHttp(handler: Handler): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    if (req.method === "OPTIONS") return preflight();
    try {
      return await handler(req);
    } catch (err) {
      return toErrorResponse(err);
    }
  };
}

/** Reads a JSON object body or throws 400 invalid_input. */
export async function readJsonObject(
  req: Request,
): Promise<Record<string, unknown>> {
  let body: unknown;
  try {
    const text = await req.text();
    body = text.trim() === "" ? undefined : JSON.parse(text);
  } catch {
    throw invalidInput("Body must be valid JSON");
  }
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    throw invalidInput("Body must be a JSON object");
  }
  return body as Record<string, unknown>;
}

/**
 * Path segments after the function name. Hosted, the URL path is
 * `/functions/v1/<name>/...` or `/<name>/...` depending on the gateway, so we
 * look for the function name and take what follows.
 */
export function subPath(url: URL, functionName: string): string[] {
  const segments = url.pathname.split("/").filter((s) => s.length > 0);
  const idx = segments.lastIndexOf(functionName);
  const rest = idx >= 0 ? segments.slice(idx + 1) : segments;
  return rest.map((s) => {
    try {
      return decodeURIComponent(s);
    } catch {
      throw invalidInput("Malformed path");
    }
  });
}
