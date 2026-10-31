export interface SkuDraft { optionValues: Record<string, string>; priceCents: number; stock: number | null; skuCode: string; }
export type SkuValidation = { ok: true } | { ok: false; errors: string[] };
export function validateSku(draft: SkuDraft): SkuValidation {
  const errors: string[] = [];
  if (!draft.skuCode.trim()) errors.push("SKU 编码不能为空");
  if (!Number.isSafeInteger(draft.priceCents) || draft.priceCents < 0) errors.push("SKU 价格必须是非负整数分");
  if (draft.stock !== null && (!Number.isSafeInteger(draft.stock) || draft.stock < 0)) errors.push("库存必须是非负整数，或 null 表示不限库存");
  if (Object.values(draft.optionValues).some(value => !value.trim())) errors.push("规格选项值不能为空");
  return errors.length ? { ok: false, errors } : { ok: true };
}
export function canReserveStock(input: { available: number | null; requested: number }): boolean {
  return Number.isSafeInteger(input.requested) && input.requested > 0 && (input.available === null || (Number.isSafeInteger(input.available) && input.available >= input.requested));
}
export function remainingStock(available: number | null, reserved: number): number | null {
  if (available === null) return null;
  if (!Number.isSafeInteger(reserved) || reserved < 0 || reserved > available) throw new RangeError("库存预留数量无效");
  return available - reserved;
}
