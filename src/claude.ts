import type { Env, LicenseRecord } from "./types";

interface ClaudeResponse {
  content?: Array<{ type: string; text?: string }>;
}

const CACHE_TTL = 24 * 60 * 60;

export async function getClaudeInsight(
  action: "activate" | "validate",
  license: LicenseRecord,
  env: Env
): Promise<string | undefined> {
  if (!env.CLAUDE_API_KEY) return undefined;

  try {
    const day = Math.floor(Date.now() / 86400000);
    const key = `claude:${action}:${license.tier}:${day}`;
    const cached = await env.ANALYTICS.get(key);
    if (cached) return cached;

    const days = Math.max(
      0,
      Math.floor((Date.parse(license.expiresAt) - Date.now()) / 86400000)
    );

    let prompt: string;
    if (action === "activate") {
      prompt = `Generate one practical welcome sentence for a DiskBuddy ${license.tier} license user.`;
    } else if (days <= 30) {
      prompt = `Generate one non-pushy sentence reminding a DiskBuddy ${license.tier} user that their license expires in ${days} days.`;
    } else if (license.tier === "pro") {
      prompt = "Generate one practical DiskBuddy power-user tip involving developer caches, storage analysis, or advanced cleanup.";
    } else {
      prompt = "Generate one practical DiskBuddy disk-maintenance tip.";
    }

    const response = await fetch(env.CLAUDE_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": env.CLAUDE_API_KEY,
        "anthropic-version": "2023-06-01"
      },
      body: JSON.stringify({
        model: env.CLAUDE_MODEL,
        max_tokens: 60,
        system:
          "You write concise DiskBuddy UI messages. Maximum 15 words. No emojis. No user names. No personal data. Return only the sentence.",
        messages: [{ role: "user", content: prompt }]
      })
    });

    if (!response.ok) return undefined;

    const data = await response.json() as ClaudeResponse;
    const text = data.content?.find(x => x.type === "text")?.text?.trim();

    if (!text || text.length > 180) return undefined;

    await env.ANALYTICS.put(key, text, { expirationTtl: CACHE_TTL });
    return text;
  } catch {
    return undefined;
  }
}
