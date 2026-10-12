import type { Env, LicenseRecord, RevokeRequest } from "./types";
import { errorResponse, jsonResponse, readJson } from "./responses";
import { validateRevoke, validLicenseID } from "./validation";
import { activationSnapshot, clearActivations } from "./activation";
import { requireSecret } from "./crypto";
import { logAnalytics } from "./analytics";

export function requireAdmin(
  request: Request,
  env: Env
): boolean {
  // Fail closed if the secret was never configured. Previously an undefined
  // binding compared equal to the string "undefined", so `Bearer undefined`
  // was accepted as admin.
  let expected: string;
  try {
    expected = requireSecret(env.ADMIN_API_KEY, "ADMIN_API_KEY");
  } catch {
    return false;
  }
  const auth = request.headers.get("Authorization") || "";
  if (!auth.startsWith("Bearer ")) return false;
  const provided = auth.slice(7);
  if (provided.length !== expected.length) return false;
  return timingSafeEqual(provided, expected);
}

function timingSafeEqual(a: string, b: string): boolean {
  const aa = new TextEncoder().encode(a);
  const bb = new TextEncoder().encode(b);
  if (aa.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < aa.length; i++) diff |= aa[i] ^ bb[i];
  return diff === 0;
}

export async function handleRevoke(
  request: Request,
  env: Env
): Promise<Response> {
  if (!requireAdmin(request, env)) {
    return errorResponse(request, env, "unauthorized", "Invalid admin credentials.", 401);
  }

  const bodyOrResponse = await readJson<RevokeRequest>(request, env);
  if (bodyOrResponse instanceof Response) return bodyOrResponse;
  const body = bodyOrResponse;

  const invalid = validateRevoke(body);
  if (invalid) return errorResponse(request, env, "invalid_request", invalid, 400);

  const license = await env.LICENSES.get<LicenseRecord>(body.license_id, "json");
  if (!license) return errorResponse(request, env, "not_found", "License not found.", 404);

  const now = new Date().toISOString();
  license.revoked = true;
  license.revokedAt = now;
  license.revokedReason = body.reason || "Admin revocation";

  await env.LICENSES.put(body.license_id, JSON.stringify(license));
  await env.REVOCATIONS.put(
    body.license_id,
    JSON.stringify({
      revokedAt: now,
      reason: license.revokedReason
    })
  );

  const snapshot = await activationSnapshot(body.license_id, env);
  const removed = Number(snapshot.count || 0);

  await clearActivations(body.license_id, env);

  await logAnalytics({
    event: "revoke",
    licenseID: body.license_id,
    timestamp: now,
    metadata: { reason: license.revokedReason }
  }, env);

  return jsonResponse(request, env, {
    success: true,
    license_id: body.license_id,
    activations_removed: removed,
    message: `License ${body.license_id} revoked.`
  });
}

export async function handleListActivations(
  request: Request,
  url: URL,
  env: Env
): Promise<Response> {
  if (!requireAdmin(request, env)) {
    return errorResponse(request, env, "unauthorized", "Invalid admin credentials.", 401);
  }

  const licenseID = url.searchParams.get("license_id");
  if (!licenseID || !validLicenseID(licenseID)) {
    return errorResponse(request, env, "invalid_request", "Valid license_id required.", 400);
  }

  const snapshot = await activationSnapshot(licenseID, env);

  return jsonResponse(request, env, {
    license_id: licenseID,
    count: snapshot.count || 0,
    activations: snapshot.activations || {}
  });
}

export async function handleAdminStats(
  request: Request,
  env: Env
): Promise<Response> {
  if (!requireAdmin(request, env)) {
    return errorResponse(request, env, "unauthorized", "Invalid admin credentials.", 401);
  }

  let totalLicenses = 0;
  let cursor: string | undefined;
  const tierBreakdown: Record<string, number> = {};

  do {
    const page = await env.LICENSES.list({ cursor, limit: 1000 });
    for (const key of page.keys) {
      if (key.name.includes(":")) continue;
      totalLicenses++;
      const license = await env.LICENSES.get<LicenseRecord>(key.name, "json");
      if (license) {
        tierBreakdown[license.tier] = (tierBreakdown[license.tier] || 0) + 1;
      }
    }
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);

  let totalRevocations = 0;
  cursor = undefined;

  do {
    const page = await env.REVOCATIONS.list({ cursor, limit: 1000 });
    totalRevocations += page.keys.length;
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);

  return jsonResponse(request, env, {
    total_licenses: totalLicenses,
    total_revocations: totalRevocations,
    tier_breakdown: tierBreakdown,
    timestamp: new Date().toISOString()
  });
}
