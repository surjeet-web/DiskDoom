import crypto from "node:crypto";

const args = process.argv.slice(2);

const tier = (args.find(x => x.startsWith("--tier="))?.split("=")[1] || "personal");
const email = args.find(x => x.startsWith("--email="))?.split("=")[1];
const days = Number(args.find(x => x.startsWith("--days="))?.split("=")[1] || "365");
const machines = Number(args.find(x => x.startsWith("--machines="))?.split("=")[1] || tierMax(tier));

if (!email) {
  console.error("Usage: npm run generate -- --email=user@example.com --tier=pro --days=365 --machines=3");
  process.exit(1);
}

if (!["trial", "personal", "pro", "team"].includes(tier)) {
  console.error("Invalid tier.");
  process.exit(1);
}

const licenseID = `DB-${crypto.randomBytes(12).toString("hex").toUpperCase()}`;
const record = {
  licenseID,
  tier,
  email: email.trim().toLowerCase(),
  productID: "com.diskbuddy.app",
  expiresAt: new Date(Date.now() + days * 86400000).toISOString(),
  maxActivations: Math.max(1, machines),
  hardwareBound: true,
  issuedAt: new Date().toISOString(),
  revoked: false
};

console.log(JSON.stringify(record, null, 2));
console.log("\nPut into KV:");
console.log(
  `npx wrangler kv key put --binding=LICENSES "${licenseID}" '${JSON.stringify(record)}'`
);

function tierMax(t: string): number {
  return t === "trial" || t === "personal" ? 1 : t === "pro" ? 3 : 10;
}
