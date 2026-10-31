export interface ApprovalRecord {
  requestId: string;
  requesterUserId: string;
  approverUserId: string;
  approvalStage: "first" | "second";
  approved: boolean;
}

export function validateTwoPersonApproval(records: ApprovalRecord[]): { ok: true } | { ok: false; reason: string } {
  const approved = records.filter(record => record.approved);
  if (approved.length < 2) return { ok: false, reason: "需要两名审批人完成审批" };
  const users = new Set(approved.map(record => record.approverUserId));
  if (users.size !== approved.length) return { ok: false, reason: "同一人员不能重复审批" };
  if (approved.some(record => record.approverUserId === record.requesterUserId)) {
    return { ok: false, reason: "申请人不能审批自己的申请" };
  }
  if (new Set(approved.map(record => record.requestId)).size !== 1) {
    return { ok: false, reason: "审批记录必须属于同一申请" };
  }
  return { ok: true };
}
