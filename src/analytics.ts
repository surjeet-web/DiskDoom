import type { AnalyticsEvent, Env } from "./types";

export async function logAnalytics(
  event: AnalyticsEvent,
  env: Env
): Promise<void> {
  const key = `${event.event}:${event.licenseID}:${Date.now()}:${crypto.randomUUID()}`;
  await env.ANALYTICS.put(key, JSON.stringify(event), {
    expirationTtl: 90 * 24 * 60 * 60
  });
}
