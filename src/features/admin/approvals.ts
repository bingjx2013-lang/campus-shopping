export interface Approval { actorId: string; decision: "approve" | "reject" }
export interface ApprovalPolicy { requiredApprovals: number; prohibitRequesterApproval: boolean }

/** Use for high-value adjustments and abnormal refunds. Identity must come from trusted session context. */
export function validateApprovals(
  requesterId: string,
  approvals: readonly Approval[],
  policy: ApprovalPolicy = { requiredApprovals: 2, prohibitRequesterApproval: true },
): string[] {
  const errors: string[] = [];
  if (!Number.isInteger(policy.requiredApprovals) || policy.requiredApprovals < 1) return ["INVALID_APPROVAL_POLICY"];
  const approved = approvals.filter((a) => a.decision === "approve");
  const ids = approved.map((a) => a.actorId);
  if (ids.some((id) => !id.trim())) errors.push("APPROVER_REQUIRED");
  if (new Set(ids).size !== ids.length) errors.push("DUPLICATE_APPROVER");
  if (policy.prohibitRequesterApproval && ids.includes(requesterId)) errors.push("REQUESTER_CANNOT_APPROVE");
  if (ids.length < policy.requiredApprovals) errors.push("INSUFFICIENT_APPROVALS");
  return errors;
}
