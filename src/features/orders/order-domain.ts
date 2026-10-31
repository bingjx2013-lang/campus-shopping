export type OrderStatus="pending_payment"|"paid"|"processing"|"shipped"|"completed"|"cancelled"|"after_sales";
const ALLOWED:Record<OrderStatus,readonly OrderStatus[]>={pending_payment:["paid","cancelled"],paid:["processing","cancelled","after_sales"],processing:["shipped","cancelled","after_sales"],shipped:["completed","after_sales"],completed:["after_sales"],cancelled:[],after_sales:["paid","processing","shipped","completed","cancelled"]};
export function canTransitionOrder(f:OrderStatus,t:OrderStatus):boolean{return ALLOWED[f].includes(t)}
export function shouldPauseAutoReceipt(s:OrderStatus,a:boolean):boolean{return a||s==="after_sales"}
