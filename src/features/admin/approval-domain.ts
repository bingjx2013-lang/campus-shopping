export interface ApprovalRecord{requestId:string;requesterUserId:string;approverUserId:string;approvalStage:"first"|"second";approved:boolean}
export function validateTwoPersonApproval(records:ApprovalRecord[]):{ok:true}|{ok:false;reason:string}{
 const a=records.filter(r=>r.approved);
 if(a.length!==2)return{ok:false,reason:"必须恰好由两名审批人完成审批"};
 if(new Set(a.map(r=>r.approverUserId)).size!==2)return{ok:false,reason:"同一人员不能重复审批"};
 if(a.some(r=>r.approverUserId===r.requesterUserId))return{ok:false,reason:"申请人不能审批自己的申请"};
 if(new Set(a.map(r=>r.requestId)).size!==1)return{ok:false,reason:"审批记录必须属于同一申请"};
 if(new Set(a.map(r=>r.requesterUserId)).size!==1)return{ok:false,reason:"审批记录的申请人必须一致"};
 if(new Set(a.map(r=>r.approvalStage)).size!==2)return{ok:false,reason:"必须分别完成第一审批和第二审批"};
 return{ok:true};
}
