import { readFileSync, writeFileSync } from "node:fs";
import crypto from "node:crypto";

const args = process.argv.slice(2);
const file = args.find(x => x.startsWith("--file="))?.split("=")[1];

if (!file) {
  console.error("Usage: npm run seed -- --file=customers.csv");
  console.error("CSV: email,tier,days,machines");
  process.exit(1);
}

const lines = readFileSync(file, "utf8")
  .split(/\r?\n/)
  .map(x => x.trim())
  .filter(Boolean);

const records = [];

for (const line of lines) {
  const [rawEmail, rawTier = "personal", rawDays = "365", rawMachines = ""] =
    line.split(",").map(x => x.trim());

  if (!rawEmail) continue;

  const tier = rawTier;
  const machines = Number(rawMachines) || tierMax(tier);
  const days = Number(rawDays);

  const licenseID = `DB-${crypto.randomBytes(12).toString("hex").toUpperCase()}`;

  records.push({
    key: licenseID,
    value: JSON.stringify({
      licenseID,
      tier,
      email: rawEmail.toLowerCase(),
      productID: "com.diskbuddy.app",
      expiresAt: new Date(Date.now() + days * 86400000).toISOString(),
      maxActivations: Math.max(1, machines),
      hardwareBound: true,
      issuedAt: new Date().toISOString(),
      revoked: false
    })
  });
}

writeFileSync("seed-bulk.json", JSON.stringify(records, null, 2));
console.log(`Generated ${records.length} licenses in seed-bulk.json`);
console.log("Run:");
console.log("npx wrangler kv bulk put --binding=LICENSES seed-bulk.json");

function tierMax(t: string): number {
  return t === "trial" || t === "personal" ? 1 : t === "pro" ? 3 : 10;
}
