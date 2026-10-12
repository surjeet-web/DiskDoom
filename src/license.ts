import type { Env, LicenseRecord, ValidateRequest, ValidateResponse } from "./types";
import { errorResponse, jsonResponse, readJson } from "./responses";
import { validateValidate } from "./validation";
import { activationSnapshot, touchActivation } from "./activation";
import { verifyDeviceToken, requireSecret } from "./crypto";
import { logAnalytics } from "./analytics";
import { getClaudeInsight } from "./claude";

export async function handleValidate(
  request: Request,
  env: Env
): Promise<Response> {
  if (!(await import("./rate-limit")).checkIPRateLimit(request, env, "validate", 120, 60)) {
    return errorResponse(request, env, "rate_limited", "Too many requests.", 429);
  }

  const bodyOrResponse = await readJson<ValidateRequest>(request, env);
  if (bodyOrResponse instanceof Response) return bodyOrResponse;
  const body = bodyOrResponse;

  const invalid = validateValidate(body);
  if (invalid) return errorResponse(request, env, "invalid_request", invalid, 400);

  const license = await env.LICENSES.get<LicenseRecord>(body.license_id, "json");

  if (!license) {
    return errorResponse(request, env, "not_found", "License not found.", 404);
  }

  if (license.productID !== env.PRODUCT_ID) {
    return errorResponse(request, env, "wrong_product", "License belongs to another product.", 403);
  }

  if (license.revoked || await env.REVOCATIONS.get(body.license_id)) {
    return jsonResponse(request, env, {
      status: "revoked",
      active_machines: 0,
      message: "This license has been revoked.",
      timestamp: new Date().toISOString()
    } satisfies ValidateResponse);
  }

  if (Date.parse(license.expiresAt) <= Date.now()) {
    return jsonResponse(request, env, {
      status: "expired",
      active_machines: 0,
      message: "This license has expired.",
      timestamp: new Date().toISOString()
    } satisfies ValidateResponse);
  }

  const snapshot = await activationSnapshot(license.licenseID, env);
  const activations = (snapshot.activations || {}) as Record<string, {
    machineID: string;
    hardwareHash: string;
  }>;
  const activeMachines = Number(snapshot.count || Object.keys(activations).length);

  const token = body.device_token
    ? await verifyDeviceToken(
        body.device_token,
        requireSecret(env.DEVICE_TOKEN_SECRET, "DEVICE_TOKEN_SECRET")
      )
    : null;

  const tokenMatches =
    token &&
    token.licenseID === license.licenseID &&
    token.hardwareHash === body.hardware_hash;

  const machine = activations[body.hardware_hash];

  if (machine) {
    await touchActivation(license, body, env);

    await logAnalytics({
      event: "validate",
      licenseID: license.licenseID,
      machineID: body.machine_id,
      timestamp: new Date().toISOString(),
      metadata: { app_version: body.app_version }
    }, env);

    const insight = await getClaudeInsight("validate", license, env);

    const response: ValidateResponse = {
      status: "valid",
      active_machines: activeMachines,
      message: "License valid.",
      timestamp: new Date().toISOString(),
      ...(env.LATEST_APP_VERSION !== body.app_version
        ? { update_available: env.LATEST_APP_VERSION }
        : {}),
      ...(insight ? { claude_insight: insight } : {}),
      device_token_required: !tokenMatches
    };

    return jsonResponse(request, env, response);
  }

  if (activeMachines >= license.maxActivations) {
    return jsonResponse(request, env, {
      status: "activation_limit_reached",
      active_machines: activeMachines,
      message: `Activation limit reached (${activeMachines}/${license.maxActivations}).`,
      timestamp: new Date().toISOString()
    } satisfies ValidateResponse);
  }

  return jsonResponse(request, env, {
    status: "unknown",
    active_machines: activeMachines,
    message: "Machine is not activated. Call /activate first.",
    timestamp: new Date().toISOString(),
    device_token_required: true
  } satisfies ValidateResponse);
}
