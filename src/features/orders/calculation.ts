export interface OrderLineInput {
  unitPriceCents: number;
  quantity: number;
  discountCents?: number;
}
export interface OrderTotals {
  itemSubtotalCents: number;
  discountCents: number;
  shippingCents: number;
  payableCents: number;
}

/** Computes a checkout total in integer cents; this is a pure calculation, not a payment operation. */
export function calculateOrderTotals(
  lines: readonly OrderLineInput[],
  shippingCents: number,
): OrderTotals {
  if (lines.length === 0) throw new RangeError("订单至少需要一个商品");
  if (!Number.isSafeInteger(shippingCents) || shippingCents < 0) {
    throw new RangeError("运费必须是非负整数分");
  }
  let itemSubtotalCents = 0;
  let discountCents = 0;
  for (const line of lines) {
    if (!Number.isSafeInteger(line.unitPriceCents) || line.unitPriceCents < 0
      || !Number.isSafeInteger(line.quantity) || line.quantity <= 0) {
      throw new RangeError("商品单价或数量无效");
    }
    const lineTotal = line.unitPriceCents * line.quantity;
    const lineDiscount = line.discountCents ?? 0;
    if (!Number.isSafeInteger(lineTotal) || !Number.isSafeInteger(lineDiscount)
      || lineDiscount < 0 || lineDiscount > lineTotal) {
      throw new RangeError("商品金额或优惠金额无效");
    }
    itemSubtotalCents += lineTotal;
    discountCents += lineDiscount;
    if (!Number.isSafeInteger(itemSubtotalCents) || !Number.isSafeInteger(discountCents)) {
      throw new RangeError("订单金额超出安全整数范围");
    }
  }
  const payableCents = itemSubtotalCents - discountCents + shippingCents;
  if (!Number.isSafeInteger(payableCents)) throw new RangeError("应付金额超出安全整数范围");
  return { itemSubtotalCents, discountCents, shippingCents, payableCents };
}
