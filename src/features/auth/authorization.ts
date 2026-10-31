/** Authorization policy foundation. Persistence and identity verification are supplied by adapters. */
export const ADMIN_ROLES = ["finance", "food_review", "customer_support", "security_admin"] as const;
export type AdminRole = (typeof ADMIN_ROLES)[number];
export type Permission =
  | "merchant.review" | "food.credential.review" | "support.case.manage"
  | "security.account.lock" | "finance.ledger.read" | "finance.settlement.approve"
  | "finance.adjustment.propose" | "finance.adjustment.approve";

const ROLE_PERMISSIONS: Record<AdminRole, readonly Permission[]> = {
  finance: ["finance.ledger.read", "finance.settlement.approve", "finance.adjustment.propose", "finance.adjustment.approve"],
  food_review: ["food.credential.review", "merchant.review"],
  customer_support: ["support.case.manage"],
  security_admin: ["security.account.lock"],
};

export function hasPermission(roles: readonly AdminRole[], permission: Permission): boolean {
  return roles.some((role) => ROLE_PERMISSIONS[role].includes(permission));
}

/** The platform is permanently scoped to 明德中英文学校; this is not tenant isolation. */
export const PLATFORM_SCHOOL_NAME = "明德中英文学校";

/** Never allow an unauthenticated caller to gain access through an absent role list. */
export function canAccess(roles: readonly AdminRole[] | null | undefined, permission: Permission): boolean {
  return Array.isArray(roles) && hasPermission(roles, permission);
}
