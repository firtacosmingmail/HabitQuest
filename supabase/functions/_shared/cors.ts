/** CORS headers so the Flutter web build can call the functions. */
export const corsHeaders: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, PUT, DELETE, OPTIONS",
  "access-control-allow-headers": "authorization, apikey, content-type, x-client-info",
  "access-control-max-age": "86400",
};

/** Answers a CORS preflight. */
export function preflight(): Response {
  return new Response("ok", { status: 200, headers: corsHeaders });
}
