export interface SkuDraft {
  id: string;
  optionValues: Record<string, string>;
  priceMinor: number;
  stock: number | null; // null means unlimited stock
}
export interface StockResult { ok: boolean; available: number | null; reason?: "invalid_quantity" | "insufficient_stock" }

export function validateSku(sku: SkuDraft): string[] {
  const errors: string[] = [];
  if (!sku.id.trim()) errors.push("SKU_ID_REQUIRED");
  if (!Number.isSafeInteger(sku.priceMinor) || sku.priceMinor < 0) errors.push("INVALID_PRICE");
  if (sku.stock !== null && (!Number.isSafeInteger(sku.stock) || sku.stock < 0)) errors.push("INVALID_STOCK");
  for (const [key, value] of Object.entries(sku.optionValues)) {
    if (!key.trim() || !value.trim()) errors.push("INVALID_OPTION_VALUE");
  }
  return errors;
}

/** Pure pre-check only. Real reservations must use an atomic DB conditional update/row lock. */
export function reserveStock(available: number | null, quantity: number): StockResult {
  if (!Number.isSafeInteger(quantity) || quantity <= 0) return { ok: false, available, reason: "invalid_quantity" };
  if (available === null) return { ok: true, available: null };
  if (available < quantity) return { ok: false, available, reason: "insufficient_stock" };
  return { ok: true, available: available - quantity };
}

export function releaseStock(available: number | null, quantity: number): StockResult {
  if (!Number.isSafeInteger(quantity) || quantity <= 0) return { ok: false, available, reason: "invalid_quantity" };
  if (available === null) return { ok: true, available: null };
  return { ok: true, available: available + quantity };
}
