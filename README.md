# DiskBuddy License Server

Production-oriented Cloudflare Workers license backend for DiskBuddy.

## Architecture

- Cloudflare Worker: HTTP API/router
- Cloudflare KV: licenses, revocations, analytics, coarse IP rate limits
- Cloudflare Durable Objects: authoritative per-license activation state and serialization
- HMAC-SHA256: server-issued device tokens
- Claude: optional advisory copy + anomaly analysis only
- No public revocation list
- No activation counter stored separately from activation state

## Endpoints

### Public

`GET /v1/health`

`POST /v1/activate`

`POST /v1/validate`

`POST /v1/deactivate`

### Admin

`POST /v1/admin/revoke`

`GET /v1/admin/activations?license_id=DB-...`

`GET /v1/admin/stats`

All admin endpoints require:

`Authorization: Bearer <ADMIN_API_KEY>`

## 1. Install

```bash
npm install
```

## 2. Create KV namespaces

```bash
npx wrangler kv namespace create LICENSES
npx wrangler kv namespace create REVOCATIONS
npx wrangler kv namespace create ANALYTICS
npx wrangler kv namespace create RATE_LIMITS
```

Copy each returned namespace ID into `wrangler.jsonc`.

## 3. Set secrets

Generate strong random values:

```bash
openssl rand -hex 32
```

Then:

```bash
npx wrangler secret put ADMIN_API_KEY
npx wrangler secret put DEVICE_TOKEN_SECRET
npx wrangler secret put CLAUDE_API_KEY
```

Claude is optional. The server works without it.

## 4. Local development

```bash
npm run typecheck
npm test
npm run dev
```

## 5. Deploy

```bash
npm run deploy
```

## 6. Custom domain

Create a Worker route/custom domain in Cloudflare for:

`api.diskbuddy.com`

Do not put `api.diskbuddy.com` in the Worker code. Cloudflare routes the hostname to the Worker.

## 7. Generate a license

```bash
npm run generate -- --email=test@example.com --tier=pro --days=365 --machines=3
```

Copy the generated `wrangler kv key put` command and run it.

## 8. Activate

```bash
curl -X POST https://api.diskbuddy.com/v1/activate \
  -H 'Content-Type: application/json' \
  -d '{
    "license_id":"DB-XXXXXXXX",
    "email":"test@example.com",
    "hardware_hash":"hardware-hash-generated-by-diskbuddy",
    "machine_id":"mac-machine-id",
    "platform_uuid":"platform-uuid",
    "app_version":"1.0.0"
  }'
```

The response contains a `device_token`. Store it in macOS Keychain.

## 9. Validate

Send the stored device token:

```bash
curl -X POST https://api.diskbuddy.com/v1/validate \
  -H 'Content-Type: application/json' \
  -d '{
    "license_id":"DB-XXXXXXXX",
    "hardware_hash":"hardware-hash-generated-by-diskbuddy",
    "machine_id":"mac-machine-id",
    "platform_uuid":"platform-uuid",
    "app_version":"1.0.0",
    "device_token":"DEVICE_TOKEN"
  }'
```

## 10. Deactivate

```bash
curl -X POST https://api.diskbuddy.com/v1/deactivate \
  -H 'Content-Type: application/json' \
  -d '{
    "license_id":"DB-XXXXXXXX",
    "hardware_hash":"hardware-hash-generated-by-diskbuddy",
    "device_token":"DEVICE_TOKEN"
  }'
```

## Security model

The Durable Object is authoritative for activation slots. This prevents the classic race where two simultaneous activation requests both see an available slot.

The client-provided hardware hash is a device identifier, not a cryptographic proof of hardware ownership. A determined attacker who controls the client can spoof client-side identifiers.

The server-issued device token is HMAC signed and required for deactivation. Tokens expire after 180 days and should be refreshed by reactivation.

Claude never decides normal license validity, expiry, activation limits, or revocation. If Claude is unavailable, licensing continues normally.

## Important production notes

1. Keep `ADMIN_API_KEY` and `DEVICE_TOKEN_SECRET` in Wrangler secrets, never in source control.
2. Do not put the Anthropic key in the macOS app.
3. Keep admin endpoints out of the public app UI.
4. Do not expose a public revocation database.
5. The Durable Object is the source of truth for active machines.
6. KV is eventually consistent and is intentionally not used for activation-slot locking.
7. For high-value paid licenses, consider an external payment provider webhook that creates/revokes license records.
8. The macOS client should store the device token in Keychain, not UserDefaults.
