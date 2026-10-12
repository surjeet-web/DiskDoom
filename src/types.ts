export type Tier = "trial" | "personal" | "pro" | "team";

export interface LicenseRecord {
  licenseID: string;
  tier: Tier;
  email: string;
  productID: string;
  expiresAt: string;
  maxActivations: number;
  hardwareBound: boolean;
  issuedAt: string;
  revoked: boolean;
  revokedAt?: string;
  revokedReason?: string;
  metadata?: Record<string, string>;
}

export interface ActivationRecord {
  licenseID: string;
  machineID: string;
  platformUUID: string;
  hardwareHash: string;
  activatedAt: string;
  lastSeenAt: string;
  appVersion: string;
  tokenVersion: number;
}

export interface ActivateRequest {
  license_id: string;
  email: string;
  hardware_hash: string;
  machine_id: string;
  platform_uuid: string;
  app_version: string;
}

export interface ValidateRequest {
  license_id: string;
  hardware_hash: string;
  machine_id: string;
  platform_uuid: string;
  app_version: string;
  device_token?: string;
}

export interface DeactivateRequest {
  license_id: string;
  hardware_hash: string;
  device_token: string;
}

export interface RevokeRequest {
  license_id: string;
  reason?: string;
}

export interface ValidateResponse {
  status:
    | "valid"
    | "revoked"
    | "activation_limit_reached"
    | "expired"
    | "unknown";
  active_machines: number;
  message: string;
  timestamp: string;
  update_available?: string;
  claude_insight?: string;
  device_token_required?: boolean;
}

export interface ActivateResponse {
  success: boolean;
  machine_id: string;
  message: string;
  device_token?: string;
  claude_insight?: string;
}

export interface DeactivateResponse {
  success: boolean;
  message: string;
}

export interface ErrorResponse {
  error: "error";
  code: string;
  message: string;
  request_id: string;
}

export interface AnalyticsEvent {
  event:
    | "activate"
    | "validate"
    | "deactivate"
    | "revoke"
    | "anomaly_detected";
  licenseID: string;
  machineID?: string;
  timestamp: string;
  metadata?: Record<string, string>;
}

export interface Env {
  ENVIRONMENT: string;
  CLAUDE_API_URL: string;
  CLAUDE_MODEL: string;
  CLAUDE_API_KEY?: string;
  ADMIN_API_KEY: string;
  DEVICE_TOKEN_SECRET: string;
  ALLOWED_ORIGINS: string;
  PRODUCT_ID: string;
  LATEST_APP_VERSION: string;
  MAX_BODY_BYTES?: string;

  LICENSES: KVNamespace;
  REVOCATIONS: KVNamespace;
  ANALYTICS: KVNamespace;
  RATE_LIMITS: KVNamespace;
  LICENSE_DO: DurableObjectNamespace;
}

export interface DOActivation {
  machineID: string;
  platformUUID: string;
  hardwareHash: string;
  activatedAt: string;
  lastSeenAt: string;
  appVersion: string;
  tokenVersion: number;
}

export interface DOState {
  licenseID: string;
  activations: Record<string, DOActivation>;
  windowStartedAt: number;
  activationAttempts: number;
}
