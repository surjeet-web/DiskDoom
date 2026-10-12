import type { Env, ErrorResponse } from "./types";

export function requestId(): string {
  return crypto.randomUUID();
}

export function getAllowedOrigin(request: Request, env: Env): string {
  const origin = request.headers.get("Origin");
  if (!origin) return "";
  const allowed = env.ALLOWED_ORIGINS
    .split(",")
    .map(x => x.trim())
    .filter(Boolean);
  return allowed.includes(origin) ? origin : "";
}

export function corsHeaders(request: Request, env: Env): Record<string, string> {
  const origin = getAllowedOrigin(request, env);
  return {
    ...(origin ? {
      "Access-Control-Allow-Origin": origin,
      "Vary": "Origin"
    } : {}),
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Max-Age": "86400"
  };
}

export function jsonResponse(
  request: Request,
  env: Env,
  data: unknown,
  status = 200,
  extra: Record<string, string> = {}
): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...corsHeaders(request, env),
      ...extra
    }
  });
}

export function errorResponse(
  request: Request,
  env: Env,
  code: string,
  message: string,
  status = 400
): Response {
  const body: ErrorResponse = {
    error: "error",
    code,
    message,
    request_id: requestId()
  };
  return jsonResponse(request, env, body, status);
}

export async function readJson<T>(
  request: Request,
  env: Env
): Promise<T | Response> {
  const max = Math.max(1024, Number(env.MAX_BODY_BYTES || 32768));
  const length = Number(request.headers.get("Content-Length") || 0);
  if (length > max) {
    return errorResponse(request, env, "body_too_large", "Request body is too large.", 413);
  }

  const contentType = request.headers.get("Content-Type") || "";
  if (!contentType.toLowerCase().includes("application/json")) {
    return errorResponse(request, env, "invalid_content_type", "Content-Type must be application/json.", 415);
  }

  try {
    const text = await request.text();
    if (new TextEncoder().encode(text).byteLength > max) {
      return errorResponse(request, env, "body_too_large", "Request body is too large.", 413);
    }
    return JSON.parse(text) as T;
  } catch {
    return errorResponse(request, env, "invalid_json", "Malformed JSON request.", 400);
  }
}
