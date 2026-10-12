import { describe, expect, it } from "vitest";
import {
  validateActivate,
  validateValidate,
  validateDeactivate,
  validLicenseID
} from "../src/validation";
import {
  signDeviceToken,
  verifyDeviceToken,
  randomTokenNonce,
  type DeviceTokenPayload
} from "../src/crypto";

const goodActivate = {
  license_id: "DB-ABCDEF123456",
  email: "user@example.com",
  hardware_hash: "aaabbbcccdddee00112233445566778899",
  machine_id: "TestMac",
  platform_uuid: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
  app_version: "1.0"
};

describe("request validation", () => {
  it("accepts a well-formed activate request", () => {
    expect(validateActivate({ ...goodActivate })).toBeNull();
  });

  it("rejects mismatched emails on activate", () => {
    expect(validateActivate({ ...goodActivate, email: "not-an-email" })).toBe(
      "Invalid email."
    );
  });

  it("rejects short hardware hashes", () => {
    expect(validateActivate({ ...goodActivate, hardware_hash: "short" })).toBe(
      "Invalid hardware_hash."
    );
  });

  it("rejects malformed license IDs", () => {
    expect(validLicenseID("DB-OK_123")).toBe(true);
    expect(validLicenseID("")).toBe(false);
    expect(validLicenseID("has space")).toBe(false);
    expect(validateValidate({ ...goodActivate })).toBeNull();
  });

  it("rejects oversized device tokens on validate", () => {
    expect(
      validateValidate({ ...goodActivate, device_token: "x".repeat(5000) })
    ).toBe("Invalid device_token.");
  });

  it("requires a real device token on deactivate", () => {
    expect(
      validateDeactivate({
        license_id: goodActivate.license_id,
        hardware_hash: goodActivate.hardware_hash,
        device_token: "too-short"
      })
    ).toBe("Invalid device_token.");
  });
});

describe("device tokens", () => {
  const secret = "test-secret-for-unit-tests-only";
  const payload: DeviceTokenPayload = {
    v: 1,
    licenseID: "DB-ABCDEF123456",
    hardwareHash: goodActivate.hardware_hash,
    issuedAt: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 3600,
    nonce: "test-nonce"
  };

  it("round-trips sign → verify", async () => {
    const token = await signDeviceToken(payload, secret);
    const verified = await verifyDeviceToken(token, secret);
    expect(verified?.licenseID).toBe(payload.licenseID);
    expect(verified?.hardwareHash).toBe(payload.hardwareHash);
  });

  it("rejects tokens signed with another secret", async () => {
    const token = await signDeviceToken(payload, secret);
    expect(await verifyDeviceToken(token, "wrong-secret")).toBeNull();
  });

  it("rejects tampered payloads", async () => {
    const token = await signDeviceToken(payload, secret);
    const [body, sig] = token.split(".");
    const tampered = `${body.replace(/.$/, body.endsWith("A") ? "B" : "A")}.${sig}`;
    expect(await verifyDeviceToken(tampered, secret)).toBeNull();
  });

  it("rejects expired tokens", async () => {
    const token = await signDeviceToken(
      { ...payload, exp: Math.floor(Date.now() / 1000) - 10 },
      secret
    );
    expect(await verifyDeviceToken(token, secret)).toBeNull();
  });

  it("rejects garbage input", async () => {
    expect(await verifyDeviceToken("not-a-token", secret)).toBeNull();
    expect(await verifyDeviceToken("", secret)).toBeNull();
  });

  it("generates unique nonces", () => {
    expect(randomTokenNonce()).not.toBe(randomTokenNonce());
  });
});
