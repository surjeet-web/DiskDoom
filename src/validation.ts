import type {
  ActivateRequest,
  DeactivateRequest,
  ValidateRequest,
  RevokeRequest,
  Tier
} from "./types";

const ID = /^[A-Za-z0-9._:-]{1,128}$/;
const HASH = /^[A-Za-z0-9._:-]{8,256}$/;
const VERSION = /^[0-9A-Za-z._+-]{1,64}$/;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function validLicenseID(value: unknown): value is string {
  return typeof value === "string" && ID.test(value);
}

export function validateActivate(body: ActivateRequest): string | null {
  if (!validLicenseID(body.license_id)) return "Invalid license_id.";
  if (typeof body.email !== "string" || !EMAIL.test(body.email) || body.email.length > 320) return "Invalid email.";
  if (typeof body.hardware_hash !== "string" || !HASH.test(body.hardware_hash)) return "Invalid hardware_hash.";
  if (typeof body.machine_id !== "string" || body.machine_id.length < 1 || body.machine_id.length > 256) return "Invalid machine_id.";
  if (typeof body.platform_uuid !== "string" || body.platform_uuid.length < 1 || body.platform_uuid.length > 256) return "Invalid platform_uuid.";
  if (typeof body.app_version !== "string" || !VERSION.test(body.app_version)) return "Invalid app_version.";
  return null;
}

export function validateValidate(body: ValidateRequest): string | null {
  if (!validLicenseID(body.license_id)) return "Invalid license_id.";
  if (typeof body.hardware_hash !== "string" || !HASH.test(body.hardware_hash)) return "Invalid hardware_hash.";
  if (typeof body.machine_id !== "string" || body.machine_id.length < 1 || body.machine_id.length > 256) return "Invalid machine_id.";
  if (typeof body.platform_uuid !== "string" || body.platform_uuid.length < 1 || body.platform_uuid.length > 256) return "Invalid platform_uuid.";
  if (typeof body.app_version !== "string" || !VERSION.test(body.app_version)) return "Invalid app_version.";
  if (body.device_token !== undefined && (typeof body.device_token !== "string" || body.device_token.length > 4096)) {
    return "Invalid device_token.";
  }
  return null;
}

export function validateDeactivate(body: DeactivateRequest): string | null {
  if (!validLicenseID(body.license_id)) return "Invalid license_id.";
  if (typeof body.hardware_hash !== "string" || !HASH.test(body.hardware_hash)) return "Invalid hardware_hash.";
  if (typeof body.device_token !== "string" || body.device_token.length < 20 || body.device_token.length > 4096) {
    return "Invalid device_token.";
  }
  return null;
}

export function validateRevoke(body: RevokeRequest): string | null {
  if (!validLicenseID(body.license_id)) return "Invalid license_id.";
  if (body.reason !== undefined && (typeof body.reason !== "string" || body.reason.length > 1000)) {
    return "Invalid reason.";
  }
  return null;
}

export function normalizeTier(value: string): Tier | null {
  if (value === "trial" || value === "personal" || value === "pro" || value === "team") return value;
  return null;
}
