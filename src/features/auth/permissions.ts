export const ADMIN_ROLES = ["finance", "food_review", "support", "security_admin"] as const;
export type AdminRole = (typeof ADMIN_ROLES)[number];

export const PERMISSIONS = [
  "orders.read", "orders.support", "food.review", "finance.read",
  "finance.settle", "finance.adjust.request", "finance.adjust.approve",
  "security.audit", "security.accounts.manage", "merchants.approve",
] as const;
export type Permission = (typeof PERMISSIONS)[number];

const ROLE_PERMISSIONS: Record<AdminRole, readonly Permission[]> = {
  finance: ["orders.read", "finance.read", "finance.settle", "finance.adjust.request"],
  food_review: ["food.review", "merchants.approve"],
  support: ["orders.read", "orders.support"],
  security_admin: ["security.audit", "security.accounts.manage"],
};

export function permissionsForRole(role: AdminRole): readonly Permission[] {
  return ROLE_PERMISSIONS[role];
}

export function hasPermission(role: AdminRole, permission: Permission): boolean {
  return ROLE_PERMISSIONS[role].includes(permission);
}

/** A requester cannot approve their own financial adjustment. */
export function canApproveFinancialAdjustment(input: {
  requesterUserId: string;
  approverUserId: string;
  approverRole: AdminRole;
}): boolean {
  return input.requesterUserId !== input.approverUserId
    && input.approverRole === "finance"
    && hasPermission(input.approverRole, "finance.adjust.approve");
}
