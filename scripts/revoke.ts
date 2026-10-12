const args = process.argv.slice(2);

const id = args.find(x => x.startsWith("--id="))?.split("=")[1];
const reason = args.find(x => x.startsWith("--reason="))?.split("=")[1] || "Admin revocation";
const key = args.find(x => x.startsWith("--admin-key="))?.split("=")[1];
const host = args.find(x => x.startsWith("--host="))?.split("=")[1] || "https://api.diskbuddy.com";

if (!id || !key) {
  console.error("Usage: npm run revoke -- --id=DB-XXX --admin-key=SECRET [--reason=reason] [--host=https://...]");
  process.exit(1);
}

const response = await fetch(`${host}/v1/admin/revoke`, {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Authorization": `Bearer ${key}`
  },
  body: JSON.stringify({
    license_id: id,
    reason
  })
});

console.log(JSON.stringify(await response.json(), null, 2));
