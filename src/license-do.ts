import type { Env, DOActivation, DOState } from "./types";

const EMPTY: DOState = {
  licenseID: "",
  activations: {},
  windowStartedAt: 0,
  activationAttempts: 0
};

export class LicenseDO {
  private state: DurableObjectState;
  private env: Env;

  constructor(state: DurableObjectState, env: Env) {
    this.state = state;
    this.env = env;
  }

  private async load(): Promise<DOState> {
    return (await this.state.storage.get<DOState>("state")) || { ...EMPTY, activations: {} };
  }

  private async save(data: DOState): Promise<void> {
    await this.state.storage.put("state", data);
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (request.method !== "POST") {
      return new Response("Method Not Allowed", { status: 405 });
    }

    const body = await request.json() as {
      op: string;
      licenseID: string;
      maxActivations?: number;
      hardwareHash?: string;
      activation?: DOActivation;
    };

    const data = await this.load();
    data.licenseID = body.licenseID;

    if (body.op === "snapshot") {
      return Response.json({
        count: Object.keys(data.activations).length,
        activations: data.activations
      });
    }

    if (body.op === "reserve_activation") {
      const now = Date.now();

      if (now - data.windowStartedAt >= 60 * 60 * 1000) {
        data.windowStartedAt = now;
        data.activationAttempts = 0;
      }

      data.activationAttempts += 1;

      if (data.activationAttempts > 20) {
        await this.save(data);
        return Response.json({ ok: false, reason: "rate_limited" }, { status: 429 });
      }

      const hash = body.hardwareHash!;
      if (data.activations[hash]) {
        return Response.json({
          ok: true,
          existing: true,
          count: Object.keys(data.activations).length,
          activation: data.activations[hash]
        });
      }

      const max = Math.max(1, Math.floor(body.maxActivations || 1));
      const count = Object.keys(data.activations).length;

      if (count >= max) {
        await this.save(data);
        return Response.json({
          ok: false,
          reason: "activation_limit",
          count,
          max
        });
      }

      data.activations[hash] = body.activation!;
      await this.save(data);

      return Response.json({
        ok: true,
        existing: false,
        count: count + 1
      });
    }

    if (body.op === "touch") {
      const hash = body.hardwareHash!;
      const existing = data.activations[hash];
      if (!existing) {
        return Response.json({ ok: false, reason: "not_activated" }, { status: 404 });
      }

      existing.lastSeenAt = new Date().toISOString();
      if (body.activation?.appVersion) existing.appVersion = body.activation.appVersion;
      await this.save(data);

      return Response.json({ ok: true, activation: existing });
    }

    if (body.op === "deactivate") {
      const hash = body.hardwareHash!;
      const existed = Boolean(data.activations[hash]);
      delete data.activations[hash];
      await this.save(data);

      return Response.json({
        ok: true,
        existed,
        count: Object.keys(data.activations).length
      });
    }

    if (body.op === "revoke") {
      data.activations = {};
      await this.save(data);
      return Response.json({ ok: true });
    }

    return Response.json({ ok: false, reason: "unknown_operation" }, { status: 400 });
  }
}
