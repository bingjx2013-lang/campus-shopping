import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const ts = require("typescript");

async function loadTs(path) {
  const source = await readFile(new URL("../" + path, import.meta.url), "utf8");
  const js = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 },
  }).outputText;
  return import("data:text/javascript;base64," + Buffer.from(js).toString("base64"));
}

const [auth, catalog, orders, calculation, finance, admin] = await Promise.all([
  loadTs("src/features/auth/permissions.ts"),
  loadTs("src/features/catalog/sku-domain.ts"),
  loadTs("src/features/orders/order-domain.ts"),
  loadTs("src/features/orders/calculation.ts"),
  loadTs("src/features/finance/ledger-domain.ts"),
  loadTs("src/features/admin/approval-domain.ts"),
]);
let passed = 0;
function test(name, fn) {
  fn();
  passed++;
  console.log("✓ " + name);
}

test("角色权限隔离与财务审批权限", () => {
  assert.equal(auth.hasPermission("finance", "finance.settle"), true);
  assert.equal(auth.hasPermission("support", "finance.settle"), false);
  assert.equal(auth.hasPermission("food_review", "food.review"), true);
  assert.equal(auth.hasPermission("finance", "finance.adjust.approve"), true);
});
test("财务申请人不能审批自己的调整", () => {
  assert.equal(auth.canApproveFinancialAdjustment({
    requesterUserId: "u1", approverUserId: "u1", approverRole: "finance",
  }), false);
  assert.equal(auth.canApproveFinancialAdjustment({
    requesterUserId: "u1", approverUserId: "u2", approverRole: "finance",
  }), true);
});
test("SKU、规格键值及库存边界", () => {
  const validSku = { skuCode: "A-1", optionValues: { size: "M" }, priceCents: 100, stock: null };
  assert.deepEqual(catalog.validateSku(validSku), { ok: true });
  assert.equal(catalog.validateSku({ ...validSku, optionValues: { " ": "M" } }).ok, false);
  assert.equal(catalog.canReserveStock({ available: null, requested: 999 }), true);
  assert.equal(catalog.canReserveStock({ available: 2, requested: 3 }), false);
  assert.equal(catalog.canReserveStock({ available: -1, requested: 1 }), false);
  assert.equal(catalog.canReserveStock({ available: 2, requested: 0 }), false);
  assert.equal(catalog.remainingStock(5, 2), 3);
  assert.equal(catalog.remainingStock(null, 10), null);
  assert.throws(() => catalog.remainingStock(2, 3), RangeError);
  assert.throws(() => catalog.remainingStock(Number.NaN, 0), RangeError);
});
test("订单状态、订单行金额和退款期间暂停自动收货", () => {
  assert.equal(orders.canTransitionOrder("pending_payment", "paid"), true);
  assert.equal(orders.canTransitionOrder("cancelled", "paid"), false);
  assert.equal(orders.calculateOrderPayable({
    itemsSubtotalCents: 1000, discountCents: 100, shippingCents: 80,
  }), 980);
  assert.throws(() => orders.calculateOrderPayable({
    itemsSubtotalCents: 100, discountCents: 101, shippingCents: 0,
  }), RangeError);
  assert.equal(orders.shouldPauseAutoReceipt("shipped", true), true);
  assert.deepEqual(calculation.calculateOrderTotals([
    { unitPriceCents: 500, quantity: 2, discountCents: 100 },
    { unitPriceCents: 300, quantity: 1 },
  ], 80), {
    itemSubtotalCents: 1300, discountCents: 100, shippingCents: 80, payableCents: 1280,
  });
  assert.throws(() => calculation.calculateOrderTotals([{ unitPriceCents: 1, quantity: 0 }], 0), RangeError);
  assert.throws(() => calculation.calculateOrderTotals([], 0), RangeError);
  assert.throws(() => calculation.calculateOrderTotals([
    { unitPriceCents: Number.MAX_SAFE_INTEGER, quantity: 2 },
  ], 0), RangeError);
});
test("账务分录借贷平衡、非法金额和冲正", () => {
  assert.deepEqual(finance.validateJournal({
    currency: "CNY",
    lines: [
      { accountCode: "cash", debitCents: 100, creditCents: 0 },
      { accountCode: "sales", debitCents: 0, creditCents: 100 },
    ],
  }), { ok: true, totalCents: 100 });
  assert.equal(finance.validateJournal({
    currency: "CNY",
    lines: [
      { accountCode: "cash", debitCents: 100, creditCents: 0 },
      { accountCode: "sales", debitCents: 0, creditCents: 90 },
    ],
  }).ok, false);
  assert.equal(finance.validateJournal({
    currency: "CNY",
    lines: [
      { accountCode: "cash", debitCents: Number.MAX_SAFE_INTEGER, creditCents: 0 },
      { accountCode: "cash2", debitCents: 1, creditCents: 0 },
      { accountCode: "sales", debitCents: 0, creditCents: Number.MAX_SAFE_INTEGER },
    ],
  }).ok, false);
  assert.equal(finance.correctionMode(), "reversal");
});
test("双人审批拒绝重复、自批、跨申请及重复审批阶段", () => {
  const first = {
    requestId: "r1", requesterUserId: "u1", approverUserId: "u2",
    approvalStage: "first", approved: true,
  };
  const second = {
    requestId: "r1", requesterUserId: "u1", approverUserId: "u3",
    approvalStage: "second", approved: true,
  };
  assert.deepEqual(admin.validateTwoPersonApproval([first, second]), { ok: true });
  assert.equal(admin.validateTwoPersonApproval([first, { ...second, approverUserId: "u2" }]).ok, false);
  assert.equal(admin.validateTwoPersonApproval([first, { ...second, approverUserId: "u1" }]).ok, false);
  assert.equal(admin.validateTwoPersonApproval([first, { ...second, approvalStage: "first" }]).ok, false);
  assert.equal(admin.validateTwoPersonApproval([first, { ...second, requestId: "r2" }]).ok, false);
  assert.equal(admin.validateTwoPersonApproval([first, { ...second, requesterUserId: "u9" }]).ok, false);
  assert.equal(admin.validateTwoPersonApproval([first, second, { ...second, approverUserId: "u4" }]).ok, false);
});
console.log(`Domain rule tests: ${passed} passed.`);
