export interface SecurityConfigIssue {
  key: "AUTH_SECRET";
  code: "MISSING" | "TOO_SHORT";
}

/** Validate required production secrets without exposing their values. */
export function validateSecurityEnvironment(
  env: Record<string, string | undefined>,
  production: boolean,
): SecurityConfigIssue[] {
  if (!production) return [];

  const issues: SecurityConfigIssue[] = [];
  const authSecret = env.AUTH_SECRET;
  if (!authSecret) {
    issues.push({ key: "AUTH_SECRET", code: "MISSING" });
  } else if (new TextEncoder().encode(authSecret).length < 32) {
    issues.push({ key: "AUTH_SECRET", code: "TOO_SHORT" });
  }
  return issues;
}

export function assertSecurityEnvironment(
  env: Record<string, string | undefined>,
  production: boolean,
): void {
  const issues = validateSecurityEnvironment(env, production);
  if (issues.length > 0) {
    const details = issues.map(({ key, code }) => `${key}:${code}`).join(", ");
    throw new Error(`Invalid production security environment (${details}). Set required secrets before starting the server.`);
  }
}
