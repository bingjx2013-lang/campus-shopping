export const ADMIN_ROLES = ["finance","food_review","support","security_admin"] as const;
export type AdminRole = (typeof ADMIN_ROLES)[number];
export type Permission = "orders.read"|"orders.support"|"food.review"|"finance.read"|"finance.settle"|"finance.adjust.request"|"finance.adjust.approve"|"security.audit"|"security.accounts.manage"|"merchants.approve";
const ROLE_PERMISSIONS:Record<AdminRole,readonly Permission[]>={finance:["orders.read","finance.read","finance.settle","finance.adjust.request"],food_review:["food.review","merchants.approve"],support:["orders.read","orders.support"],security_admin:["security.audit","security.accounts.manage"]};
export function permissionsForRole(r:AdminRole):readonly Permission[]{return ROLE_PERMISSIONS[r]}
export function hasPermission(r:AdminRole,p:Permission):boolean{return ROLE_PERMISSIONS[r].includes(p)}
export function canApproveFinancialAdjustment(i:{requesterUserId:string;approverUserId:string;approverRole:AdminRole}):boolean{return i.requesterUserId!==i.approverUserId&&i.approverRole==="finance"&&hasPermission(i.approverRole,"finance.adjust.approve")}
