export type OrderStatus="pending_payment"|"paid"|"processing"|"shipped"|"completed"|"cancelled"|"after_sales";
const ALLOWED:Record<OrderStatus,readonly OrderStatus[]>={pending_payment:["paid","cancelled"],paid:["processing","cancelled","after_sales"],processing:["shipped","cancelled","after_sales"],shipped:["completed","after_sales"],completed:["after_sales"],cancelled:[],after_sales:["paid","processing","shipped","completed","cancelled"]};
export function canTransitionOrder(f:OrderStatus,t:OrderStatus):boolean{return ALLOWED[f].includes(t)}
export interface OrderMoneyInput{itemsSubtotalCents:number;discountCents:number;shippingCents:number}
export function calculateOrderPayable(i:OrderMoneyInput):number{for(const v of Object.values(i))if(!Number.isSafeInteger(v)||v<0)throw new RangeError("订单金额必须为非负整数分");if(i.discountCents>i.itemsSubtotalCents)throw new RangeError("优惠金额不能超过商品金额");const n=i.itemsSubtotalCents-i.discountCents+i.shippingCents;if(!Number.isSafeInteger(n))throw new RangeError("订单金额超出安全范围");return n}
export function shouldPauseAutoReceipt(s:OrderStatus,a:boolean):boolean{return a||s==="after_sales"}
