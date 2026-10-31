import { assertSecurityEnvironment } from "./src/lib/security-config";

/**
 * Next.js invokes register during server startup.
 * Validate secrets only in the Node.js runtime; never log secret values.
 */
export async function register(): Promise<void> {
  if (process.env.NEXT_RUNTIME !== "nodejs") return;
  assertSecurityEnvironment(process.env, process.env.NODE_ENV === "production");
}
