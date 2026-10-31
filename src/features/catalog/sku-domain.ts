export interface SkuDraft{optionValues:Record<string,string>;priceCents:number;stock:number|null;skuCode:string}
export type SkuValidation={ok:true}|{ok:false;errors:string[]}
export function validateSku(d:SkuDraft):SkuValidation{const e:string[]=[];if(!d.skuCode.trim())e.push("SKU 编码不能为空");if(!Number.isSafeInteger(d.priceCents)||d.priceCents<0)e.push("SKU 价格必须是非负整数分");if(d.stock!==null&&(!Number.isSafeInteger(d.stock)||d.stock<0))e.push("库存必须是非负整数，或 null 表示不限库存");if(Object.values(d.optionValues).some(v=>!v.trim()))e.push("规格选项值不能为空");return e.length?{ok:false,errors:e}:{ok:true}}
export function canReserveStock(i:{available:number|null;requested:number}):boolean{return Number.isSafeInteger(i.requested)&&i.requested>0&&(i.available===null||(Number.isSafeInteger(i.available)&&i.available>=i.requested))}
export function remainingStock(a:number|null,r:number):number|null{if(a===null)return null;if(!Number.isSafeInteger(r)||r<0||r>a)throw new RangeError("库存预留数量无效");return a-r}
