export interface OrderLineInput { unitPriceMinor: number; quantity: number; discountMinor?: number }
export interface OrderTotals { itemSubtotalMinor: number; discountMinor: number; shippingMinor: number; payableMinor: number }

export function calculateOrderTotals(lines: readonly OrderLineInput[], shippingMinor: number): OrderTotals {
  if (!Number.isSafeInteger(shippingMinor) || shippingMinor < 0) throw new Error("INVALID_SHIPPING");
  let subtotal = 0;
  let discount = 0;
  for (const line of lines) {
    if (!Number.isSafeInteger(line.unitPriceMinor) || line.unitPriceMinor < 0 ||
        !Number.isSafeInteger(line.quantity) || line.quantity <= 0) throw new Error("INVALID_ORDER_LINE");
    const lineSubtotal = line.unitPriceMinor * line.quantity;
    const lineDiscount = line.discountMinor ?? 0;
    if (!Number.isSafeInteger(lineSubtotal) || !Number.isSafeInteger(lineDiscount) ||
        lineDiscount < 0 || lineDiscount > lineSubtotal) throw new Error("INVALID_LINE_DISCOUNT");
    subtotal += lineSubtotal;
    discount += lineDiscount;
  }
  const payable = subtotal - discount + shippingMinor;
  if (![subtotal, discount, payable].every(Number.isSafeInteger)) throw new Error("MONEY_OVERFLOW");
  return { itemSubtotalMinor: subtotal, discountMinor: discount, shippingMinor, payableMinor: payable };
}

export type MerchantOrderStatus = "pending_payment" | "paid" | "preparing" | "shipped" | "completed" | "cancelled" | "after_sales";
const TRANSITIONS: Record<MerchantOrderStatus, readonly MerchantOrderStatus[]> = {
  pending_payment: ["paid", "cancelled"], paid: ["preparing", "cancelled", "after_sales"],
  preparing: ["shipped", "cancelled", "after_sales"], shipped: ["completed", "after_sales"],
  completed: ["after_sales"], cancelled: [], after_sales: ["paid", "preparing", "shipped", "completed", "cancelled"],
};
export function canTransitionOrder(from: MerchantOrderStatus, to: MerchantOrderStatus): boolean {
  return TRANSITIONS[from].includes(to);
}
