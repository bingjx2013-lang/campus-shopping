export type OrderStatus =
  | "pending_payment" | "paid" | "processing" | "shipped"
  | "completed" | "cancelled" | "after_sales";

const ALLOWED: Record<OrderStatus, readonly OrderStatus[]> = {
  pending_payment: ["paid", "cancelled"],
  paid: ["processing", "cancelled", "after_sales"],
  processing: ["shipped", "cancelled", "after_sales"],
  shipped: ["completed", "after_sales"],
  completed: ["after_sales"],
  cancelled: [],
  after_sales: ["paid", "processing", "shipped", "completed", "cancelled"],
};

export function canTransitionOrder(from: OrderStatus, to: OrderStatus): boolean {
  return ALLOWED[from].includes(to);
}

export interface OrderMoneyInput {
  itemsSubtotalCents: number;
  discountCents: number;
  shippingCents: number;
}

export function calculateOrderPayable(input: OrderMoneyInput): number {
  for (const value of Object.values(input)) {
    if (!Number.isSafeInteger(value) || value < 0) throw new RangeError("订单金额必须为非负整数分");
  }
  if (input.discountCents > input.itemsSubtotalCents) throw new RangeError("优惠金额不能超过商品金额");
  const total = input.itemsSubtotalCents - input.discountCents + input.shippingCents;
  if (!Number.isSafeInteger(total)) throw new RangeError("订单金额超出安全范围");
  return total;
}

/** While after-sales is active, automatic receipt confirmation must remain paused. */
export function shouldPauseAutoReceipt(status: OrderStatus, hasOpenAfterSales: boolean): boolean {
  return hasOpenAfterSales || status === "after_sales";
}
