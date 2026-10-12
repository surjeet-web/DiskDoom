import type { Env, LicenseRecord, ActivateRequest } from "./types";
import { getClaudeAnomaly } from "./claude-anomaly";

export interface AnomalyResult {
  block: boolean;
  reason?: string;
  userMessage?: string;
}

const LIMITS = {
  hourlyAttempts: 5,
  dailyDistinctMachines: 5
};

export async function checkActivationAnomaly(
  license: LicenseRecord,
  request: ActivateRequest,
  env: Env
): Promise<AnomalyResult> {
  const hour = await countRecentActivations(license.licenseID, 60 * 60 * 1000, env);

  if (hour >= LIMITS.hourlyAttempts) {
    const analysis = await getClaudeAnomaly(
      {
        licenseID: license.licenseID,
        tier: license.tier,
        currentMachine: request.machine_id,
        recentActivationCount: hour,
        maxActivations: license.maxActivations
      },
      env
    );

    if (analysis?.action === "block") {
      return {
        block: true,
        reason: analysis.reason || "Excessive activation velocity.",
        userMessage: "Too many activation attempts. Please wait before trying again."
      };
    }
  }

  return { block: false };
}

async function countRecentActivations(
  licenseID: string,
  windowMs: number,
  env: Env
): Promise<number> {
  const cutoff = Date.now() - windowMs;
  let count = 0;
  let cursor: string | undefined;

  do {
    const page = await env.ANALYTICS.list({
      prefix: `activate:${licenseID}:`,
      cursor,
      limit: 1000
    });

    for (const key of page.keys) {
      const parts = key.name.split(":");
      const ts = Number(parts[parts.length - 2]);
      if (Number.isFinite(ts) && ts >= cutoff) count++;
    }

    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);

  return count;
}
