const encoder = new TextEncoder();

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function fromBase64url(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((value.length + 3) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, c => c.charCodeAt(0));
}

async function hmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"]
  );
}

export interface DeviceTokenPayload {
  v: 1;
  licenseID: string;
  hardwareHash: string;
  issuedAt: number;
  exp: number;
  nonce: string;
}

export async function signDeviceToken(
  payload: DeviceTokenPayload,
  secret: string
): Promise<string> {
  const body = base64url(encoder.encode(JSON.stringify(payload)));
  const key = await hmacKey(secret);
  const sig = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, encoder.encode(body))
  );
  return `${body}.${base64url(sig)}`;
}

export async function verifyDeviceToken(
  token: string,
  secret: string
): Promise<DeviceTokenPayload | null> {
  try {
    const [body, signature] = token.split(".");
    if (!body || !signature) return null;

    const key = await hmacKey(secret);
    const valid = await crypto.subtle.verify(
      "HMAC",
      key,
      fromBase64url(signature),
      encoder.encode(body)
    );
    if (!valid) return null;

    const payload = JSON.parse(
      new TextDecoder().decode(fromBase64url(body))
    ) as DeviceTokenPayload;

    if (
      payload.v !== 1 ||
      typeof payload.licenseID !== "string" ||
      typeof payload.hardwareHash !== "string" ||
      typeof payload.issuedAt !== "number" ||
      typeof payload.exp !== "number" ||
      typeof payload.nonce !== "string"
    ) return null;

    if (payload.exp <= Math.floor(Date.now() / 1000)) return null;

    return payload;
  } catch {
    return null;
  }
}

export function randomTokenNonce(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(24));
  return base64url(bytes);
}

/// Fails loudly when a required secret is missing or too short to be safe.
///
/// This exists because of a real vulnerability. `Env.ADMIN_API_KEY` is typed
/// `string`, but at runtime an undeclared Wrangler binding is `undefined`, and
/// `TextEncoder().encode(undefined)` stringifies to the 9-byte string
/// `"undefined"`. So the literal request header
/// `Authorization: Bearer undefined` compared byte-for-byte equal to the
/// "secret" and authenticated as admin, granting unlimited license
/// revocation. The same class of bug made `DEVICE_TOKEN_SECRET` fall back to
/// the publicly-known HMAC key `"undefined"`, letting anyone who has read this
/// source mint a valid device token for any license.
///
/// A misconfigured deploy must fail closed, not fail open.
export function requireSecret(
  value: string | undefined,
  name: string,
  minLength = 32
): string {
  if (typeof value !== "string" || value.length < minLength) {
    throw new Error(
      `Missing or too-short required secret: ${name} ` +
        `(need >= ${minLength} chars). Run: wrangler secret put ${name}`
    );
  }
  return value;
}
