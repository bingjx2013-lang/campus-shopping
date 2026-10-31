import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const ts = require("typescript");
async function loadTs(path) {
  const source = await readFile(new URL("../" + path, import.meta.url), "utf8");
  const js = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 } }).outputText;
  return import("data:text/javascript;base64," + Buffer.from(js).toString("base64"));
}
const [auth, catalog, orders, finance, admin] = await Promise.all([
  loadTs("src/features/auth/permissions.ts"), loadTs("src/features/catalog/sku-domain.ts"),
  loadTs("src/features/orders/order-domain.ts"), loadTs("src/features/finance/ledger-domain.ts"),
  loadTs("src/features/admin/approval-domain.ts"),
]);
let passed = 0;
function test(name, fn) { fn(); passed++; console.log("✓ " + name); }
test("角色权限按职责隔离", () => {
  assert.equal(auth.hasPermission("finance", "finance.settle"), true);
  assert.equal(auth.hasPermission("support", "finance.settle"), false);
  assert.equal(auth.hasPermission("food_review", "food.review"), true);
});
test("财务申请人不能审批自己的调整", () => {
  assert.equal(auth.canApproveFinancialAdjustment({ requesterUserId: "u1", approverUserId: "u1", approverRole: "finance" }), false);
  assert.equal(auth.canApproveFinancialAdjustment({ requesterUserId: "u1", approverUserId: "u2", approverRole: "finance" }), true);
});
test("SKU 校验与不限库存", () => {
  assert.deepEqual(catalog.validateSku({ skuCode: "A-1", optionValues: { size: "M" }, priceCents: 100, stock: null }), { ok: true });
  assert.equal(catalog.canReserveStock({ available: null, requested: 999 }), true);
  assert.equal(catalog.canReserveStock({ available: 2, requested: 3 }), false);
  assert.equal(catalog.remainingStock(5, 2), 3);
  assert.throws(() => catalog.remainingStock(2, 3), RangeError);
});
test("订单状态、金额和售后暂停自动收货", () => {
  assert.equal(orders.canTransitionOrder("pending_payment", "paid"), true);
  assert.equal(orders.canTransitionOrder("cancelled", "paid"), false);
  assert.equal(orders.calculateOrderPayable({ itemsSubtotalCents: 1000, discountCents: 100, shippingCents: 80 }), 980);
  assert.throws(() => orders.calculateOrderPayable({ itemsSubtotalCents: 100, discountCents: 101, shippingCents: 0 }), RangeError);
  assert.equal(orders.shouldPauseAutoReceipt("shipped", true), true);
});
test("账务分录借贷平衡且更正走冲正", () => {
  assert.deepEqual(finance.validateJournal({ currency: "CNY", lines: [{ accountCode: "cash", debitCents: 100, creditCents: 0 }, { accountCode: "sales", debitCents: 0, creditCents: 100 }] }), { ok: true, totalCents: 100 });
  assert.equal(finance.validateJournal({ currency: "CNY", lines: [{ accountCode: "cash", debitCents: 100, creditCents: 0 }, { accountCode: "sales", debitCents: 0, creditCents: 90 }] }).ok, false);
  assert.equal(finance.correctionMode(), "reversal");
});
test("双人审批阻止重复审批和申请人自批", () => {
  const base = [{ requestId: "r1", requesterUserId: "u1", approverUserId: "u2", approvalStage: "first", approved: true }, { requestId: "r1", requesterUserId: "u1", approverUserId: "u3", approvalStage: "second", approved: true }];
  assert.deepEqual(admin.validateTwoPersonApproval(base), { ok: true });
  assert.equal(admin.validateTwoPersonApproval([base[0], { ...base[1], approverUserId: "u2" }]).ok, false);
  assert.equal(admin.validateTwoPersonApproval([base[0], { ...base[1], approverUserId: "u1" }]).ok, false);
  assert.equal(admin.validateTwoPersonApproval([base[0], { ...base[1], approvalStage: "first" }]).ok, false);
  assert.equal(admin.validateTwoPersonApproval([...base, { ...base[1], approverUserId: "u4" }]).ok, false);
  assert.equal(admin.validateTwoPersonApproval([base[0], { ...base[1], requesterUserId: "u9" }]).ok, false);
});
console.log(`Domain rule tests: ${passed} passed.`);
