export interface SecurityConfigIssue { key: string; code: "MISSING" | "TOO_SHORT" }

/** Validate required secrets at startup. Never log or return secret values. */
export function validateSecurityEnvironment(
  env: Record<string, string | undefined>,
  production: boolean,
): SecurityConfigIssue[] {
  if (!production) return [];
  const issues: SecurityConfigIssue[] = [];
  const authSecret = env.AUTH_SECRET;
  if (!authSecret) issues.push({ key: "AUTH_SECRET", code: "MISSING" });
  else if (new TextEncoder().encode(authSecret).length < 32) {
    issues.push({ key: "AUTH_SECRET", code: "TOO_SHORT" });
  }
  return issues;
}
