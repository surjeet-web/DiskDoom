import type { Env } from "./types";

export async function checkIPRateLimit(
  request: Request,
  env: Env,
  bucket: string,
  limit: number,
  windowSeconds: number
): Promise<boolean> {
  const ip =
    request.headers.get("CF-Connecting-IP") ||
    request.headers.get("X-Forwarded-For")?.split(",")[0]?.trim() ||
    "unknown";

  const slot = Math.floor(Date.now() / (windowSeconds * 1000));
  const key = `ip:${bucket}:${ip}:${slot}`;

  const current = Number(await env.RATE_LIMITS.get(key) || "0");
  if (current >= limit) return false;

  await env.RATE_LIMITS.put(key, String(current + 1), {
    expirationTtl: windowSeconds + 60
  });

  return true;
}
