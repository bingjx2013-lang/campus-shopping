import { readFile } from "node:fs/promises";

async function readAudit(path) {
  try {
    return JSON.parse(await readFile(new URL("../" + path, import.meta.url), "utf8"));
  } catch (error) {
    throw new Error(`无法读取依赖审计文件 ${path}: ${error.message}`);
  }
}

const full = await readAudit("npm-audit-full.json");
const production = await readAudit("npm-audit-production.json");
for (const [label, audit] of [["all dependencies", full], ["production dependencies", production]]) {
  if (!audit.metadata || !audit.metadata.vulnerabilities) {
    throw new Error(`Dependency audit result for ${label} is missing vulnerability metadata; failing closed.`);
  }
}

const severities = ["low", "moderate", "high", "critical"];
const fullCounts = full.metadata.vulnerabilities;
const productionCounts = production.metadata.vulnerabilities;
const fullBlocked = (fullCounts.high ?? 0) + (fullCounts.critical ?? 0);
const productionBlocked = severities.reduce((sum, level) => sum + (productionCounts[level] ?? 0), 0);

console.log("All-dependency audit:", JSON.stringify(fullCounts));
console.log("Production-dependency audit:", JSON.stringify(productionCounts));
if (fullBlocked > 0 || productionBlocked > 0) {
  console.error("Dependency audit policy failed: remove all production vulnerabilities and all high/critical vulnerabilities.");
  process.exit(1);
}
console.log("Dependency audit policy passed (moderate development-only findings are reported for follow-up).");
