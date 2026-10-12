import type { Env } from "./types";

interface Result {
  suspicious: boolean;
  reason?: string;
  action: "allow" | "flag" | "block";
}

export async function getClaudeAnomaly(
  context: {
    licenseID: string;
    tier: string;
    currentMachine: string;
    recentActivationCount: number;
    maxActivations: number;
  },
  env: Env
): Promise<Result | undefined> {
  if (!env.CLAUDE_API_KEY) return undefined;

  try {
    const response = await fetch(env.CLAUDE_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": env.CLAUDE_API_KEY,
        "anthropic-version": "2023-06-01"
      },
      body: JSON.stringify({
        model: env.CLAUDE_MODEL,
        max_tokens: 120,
        system:
          'Analyze licensing abuse. Respond ONLY as JSON: {"suspicious":boolean,"reason":"string","action":"allow"|"flag"|"block"}. Block only clear abuse. Never block solely because of a reinstall or normal hardware change.',
        messages: [{
          role: "user",
          content:
            `License tier=${context.tier}; max=${context.maxActivations}; ` +
            `recent activation events=${context.recentActivationCount}; ` +
            `current machine=${context.currentMachine}.`
        }]
      })
    });

    if (!response.ok) return undefined;

    const data = await response.json() as {
      content?: Array<{ text?: string }>;
    };

    const raw = data.content?.find(x => x.text)?.text?.trim();
    if (!raw) return undefined;

    const parsed = JSON.parse(raw) as Result;

    if (!["allow", "flag", "block"].includes(parsed.action)) return undefined;
    if (typeof parsed.suspicious !== "boolean") return undefined;

    return parsed;
  } catch {
    return undefined;
  }
}
