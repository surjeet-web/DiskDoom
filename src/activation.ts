import type {
  Env,
  ActivateRequest,
  DeactivateRequest,
  LicenseRecord,
  ActivationRecord,
  ActivateResponse,
  DeactivateResponse
} from "./types";
import { errorResponse, jsonResponse, readJson } from "./responses";
import { validateActivate, validateDeactivate } from "./validation";
import { signDeviceToken, verifyDeviceToken, randomTokenNonce, requireSecret } from "./crypto";
import { checkActivationAnomaly } from "./anomaly";
import { logAnalytics } from "./analytics";
import { getClaudeInsight } from "./claude";

async function getLicense(
  licenseID: string,
  env: Env
): Promise<LicenseRecord | null> {
  return await env.LICENSES.get<LicenseRecord>(licenseID, "json");
}

function licenseUsable(license: LicenseRecord): boolean {
  return (
    license.productID === "com.diskbuddy.app" &&
    !license.revoked &&
    Date.parse(license.expiresAt) > Date.now()
  );
}

function doFor(env: Env, licenseID: string): DurableObjectStub {
  const id = env.LICENSE_DO.idFromName(`license:${licenseID}`);
  return env.LICENSE_DO.get(id);
}

export async function handleActivate(
  request: Request,
  env: Env
): Promise<Response> {
  if (!(await import("./rate-limit")).checkIPRateLimit(request, env, "activate", 30, 60)) {
    return errorResponse(request, env, "rate_limited", "Too many requests.", 429);
  }

  const bodyOrResponse = await readJson<ActivateRequest>(request, env);
  if (bodyOrResponse instanceof Response) return bodyOrResponse;
  const body = bodyOrResponse;

  const invalid = validateActivate(body);
  if (invalid) return errorResponse(request, env, "invalid_request", invalid, 400);

  const license = await getLicense(body.license_id, env);
  if (!license) return errorResponse(request, env, "not_found", "License not found.", 404);

  if (license.productID !== env.PRODUCT_ID) {
    return errorResponse(request, env, "wrong_product", "License belongs to another product.", 403);
  }

  if (license.revoked || await env.REVOCATIONS.get(body.license_id)) {
    return errorResponse(request, env, "revoked", "This license has been revoked.", 403);
  }

  if (Date.parse(license.expiresAt) <= Date.now()) {
    return errorResponse(request, env, "expired", "This license has expired.", 403);
  }

  if (license.email.toLowerCase() !== body.email.trim().toLowerCase()) {
    return errorResponse(request, env, "email_mismatch", "Email does not match this license.", 403);
  }

  const anomaly = await checkActivationAnomaly(license, body, env);
  if (anomaly.block) {
    await logAnalytics({
      event: "anomaly_detected",
      licenseID: license.licenseID,
      machineID: body.machine_id,
      timestamp: new Date().toISOString(),
      metadata: { reason: anomaly.reason || "unknown" }
    }, env);

    return errorResponse(request, env, "anomaly_detected", anomaly.userMessage || "Activation blocked.", 403);
  }

  const now = new Date().toISOString();
  const activation: ActivationRecord = {
    licenseID: license.licenseID,
    machineID: body.machine_id,
    platformUUID: body.platform_uuid,
    hardwareHash: body.hardware_hash,
    activatedAt: now,
    lastSeenAt: now,
    appVersion: body.app_version,
    tokenVersion: 1
  };

  const stub = doFor(env, license.licenseID);

  const result = await stub.fetch("https://license-do/activate", {
    method: "POST",
    body: JSON.stringify({
      op: "reserve_activation",
      licenseID: license.licenseID,
      maxActivations: license.maxActivations,
      hardwareHash: body.hardware_hash,
      activation: {
        machineID: activation.machineID,
        platformUUID: activation.platformUUID,
        hardwareHash: activation.hardwareHash,
        activatedAt: activation.activatedAt,
        lastSeenAt: activation.lastSeenAt,
        appVersion: activation.appVersion,
        tokenVersion: activation.tokenVersion
      }
    })
  });

  const reservation = await result.json() as {
    ok: boolean;
    existing?: boolean;
    count?: number;
    reason?: string;
    activation?: ActivationRecord;
  };

  if (!reservation.ok) {
    if (reservation.reason === "activation_limit") {
      return errorResponse(
        request,
        env,
        "activation_limit",
        `Maximum activations reached (${reservation.count}/${license.maxActivations}).`,
        403
      );
    }
    if (reservation.reason === "rate_limited") {
      return errorResponse(request, env, "rate_limited", "Too many activation attempts.", 429);
    }
    return errorResponse(request, env, "activation_failed", "Activation could not be completed.", 500);
  }

  const token = await signDeviceToken({
    v: 1,
    licenseID: license.licenseID,
    hardwareHash: body.hardware_hash,
    issuedAt: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 180 * 24 * 60 * 60,
    nonce: randomTokenNonce()
  }, requireSecret(env.DEVICE_TOKEN_SECRET, "DEVICE_TOKEN_SECRET"));

  await logAnalytics({
    event: "activate",
    licenseID: license.licenseID,
    machineID: body.machine_id,
    timestamp: now,
    metadata: {
      app_version: body.app_version,
      machine_id: body.machine_id
    }
  }, env);

  const insight = await getClaudeInsight("activate", license, env);

  const response: ActivateResponse = {
    success: true,
    machine_id: body.machine_id,
    message: reservation.existing
      ? "Machine already activated."
      : `Activated successfully. ${reservation.count}/${license.maxActivations} machines.`,
    device_token: token,
    claude_insight: insight
  };

  return jsonResponse(request, env, response);
}

export async function handleDeactivate(
  request: Request,
  env: Env
): Promise<Response> {
  if (!(await import("./rate-limit")).checkIPRateLimit(request, env, "deactivate", 20, 60)) {
    return errorResponse(request, env, "rate_limited", "Too many requests.", 429);
  }

  const bodyOrResponse = await readJson<DeactivateRequest>(request, env);
  if (bodyOrResponse instanceof Response) return bodyOrResponse;
  const body = bodyOrResponse;

  const invalid = validateDeactivate(body);
  if (invalid) return errorResponse(request, env, "invalid_request", invalid, 400);

  const token = await verifyDeviceToken(
    body.device_token,
    requireSecret(env.DEVICE_TOKEN_SECRET, "DEVICE_TOKEN_SECRET")
  );
  if (!token || token.licenseID !== body.license_id || token.hardwareHash !== body.hardware_hash) {
    return errorResponse(request, env, "invalid_device_token", "Device authentication failed.", 403);
  }

  const license = await getLicense(body.license_id, env);
  if (!license) return errorResponse(request, env, "not_found", "License not found.", 404);

  const stub = doFor(env, body.license_id);
  const result = await stub.fetch("https://license-do/deactivate", {
    method: "POST",
    body: JSON.stringify({
      op: "deactivate",
      licenseID: body.license_id,
      hardwareHash: body.hardware_hash
    })
  });

  const data = await result.json() as { ok: boolean; existed: boolean; count: number };

  await logAnalytics({
    event: "deactivate",
    licenseID: body.license_id,
    timestamp: new Date().toISOString()
  }, env);

  const response: DeactivateResponse = {
    success: true,
    message: data.existed
      ? "Machine deactivated. Activation slot freed."
      : "Machine was already inactive."
  };

  return jsonResponse(request, env, response);
}

export async function touchActivation(
  license: LicenseRecord,
  body: {
    hardware_hash: string;
    app_version: string;
  },
  env: Env
): Promise<boolean> {
  const stub = doFor(env, license.licenseID);
  const result = await stub.fetch("https://license-do/touch", {
    method: "POST",
    body: JSON.stringify({
      op: "touch",
      licenseID: license.licenseID,
      hardwareHash: body.hardware_hash,
      activation: { appVersion: body.app_version }
    })
  });
  return result.ok;
}

export async function activationSnapshot(
  licenseID: string,
  env: Env
): Promise<Record<string, unknown>> {
  const stub = doFor(env, licenseID);
  const result = await stub.fetch("https://license-do/snapshot", {
    method: "POST",
    body: JSON.stringify({ op: "snapshot", licenseID })
  });
  return await result.json() as Record<string, unknown>;
}

export async function clearActivations(
  licenseID: string,
  env: Env
): Promise<void> {
  const stub = doFor(env, licenseID);
  await stub.fetch("https://license-do/revoke", {
    method: "POST",
    body: JSON.stringify({ op: "revoke", licenseID })
  });
}
