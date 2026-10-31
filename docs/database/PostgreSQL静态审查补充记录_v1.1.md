# PostgreSQL 静态审查补充记录 v1.1

> 审查范围：`0002_campus_shopping_full_schema_v1_draft.sql`、`0003_inventory_finance_reliability_v1_draft.sql`。本记录仅为代码阅读和官方语法文档核对，不代表 PostgreSQL 实际执行、并发测试或迁移验收通过。未连接任何数据库。

## 1. 本轮结论

- 两份迁移仍为 DRAFT，禁止直接用于生产。
- PostgreSQL 官方 CREATE TRIGGER 文档确认：constraint trigger 必须是 AFTER ROW；UPDATE OF 列列表属于事件语法的一部分。因此 0003 中 `AFTER INSERT OR UPDATE OF status` 不能仅凭语法形式判定为错误。仍需在 PostgreSQL 15+ 实际执行验证。
- 当前更主要的风险在触发器函数语义、账务状态最终值校验、并发一致性与权限边界。

## 2. 新发现/待修复项

### P1：过账触发器使用事件快照状态，而非事务提交时当前状态

`assert_posted_entry_balanced()` 在延迟触发器执行时检查 `NEW.status='posted'`。若同一事务先把分录改为 posted，随后又改回 draft，队列中的旧事件仍携带 posted 的 NEW 值；函数可能按旧事件快照检查，而非读取该分录当前最终状态。建议触发器函数在执行时按 `NEW.id` 重新读取 `journal_entries.status`，并只对当前仍为 posted 的分录检查；另设计明确的不可逆过账状态机。

### P1：触发器函数对 OLD/NEW 的条件引用需消除歧义

`assert_journal_entry_balanced()` 在 INSERT/UPDATE/DELETE 混合路径中通过 CASE 表达式引用 OLD/NEW；`assert_posted_entry_balanced()` 在一个布尔表达式中同时引用 `OLD.status` 和 TG_OP。虽然逻辑上试图依赖条件分支，但不应把未定义触发器记录的字段访问安全性建立在表达式求值顺序上。建议改为显式 `IF TG_OP = ...` 分支分别读取 OLD 或 NEW，再构造待检查 entry ID；并在每种操作类型的独立测试中覆盖。

### P1：仅检查 journal_lines 和 journal_entries.status 仍需补齐删除/修改边界

需明确并测试：
- 删除 journal_entries 时是否允许已过账分录被直接删除；建议禁止删除已过账分录，采用冲销分录。
- 修改 journal_entries 的 source_type/source_id、entry_no 等关键字段是否允许；已过账后应禁止修改关键字段。
- 更新 journal_lines.entry_id 时，旧、新分录都必须检查；现有函数已有尝试，但要测试两个分录各自最终平衡/不平衡的组合。
- 修改 journal_lines.account_id、debit、credit、wallet_id 是否均纳入同一过账校验。
- 并发事务对同一 entry 的多行借贷明细并发写入时，触发器汇总是否可能出现写偏差；建议采用受控过账函数和 entry 级锁，并禁止应用角色直接改已过账明细。

### P1：账务完整性不能只靠延迟触发器

- 需要受控 posting API/函数：锁定 entry、校验借贷、状态迁移、写审计事件，在单一事务完成。
- 应用运行账号不得直接 UPDATE/DELETE 已过账 journal_entries 或 journal_lines。
- 应补充冲销/更正模型，不允许覆盖历史分录。
- 应明确金额精度、币种、汇率与舍入规则；当前借贷汇总按 numeric(18,2) 计算，需确认平台是否只支持 CNY 两位小数。

### P1：0002 表约束和业务规则缺口

- 多处状态字段为自由 text（如订单、售后、退款、发货、支付等），需统一 CHECK/字典表及状态迁移规则，避免拼写错误和非法跳转。
- `wallets.owner_type + owner_id` 是多态关联，数据库无法通过普通 FK 保证 owner_id 对应真实 user/merchant/platform 记录；需改为可验证的账户主体模型或由受控函数严格校验。
- `student_profiles.guardian_user_id` 仅支持单一监护人；需确认业务是否需要多个监护人及关系表。
- `addresses` 的默认地址缺少每用户最多一个默认地址的部分唯一索引。
- `product_options`、`product_option_values`、`skus.option_snapshot` 之间缺少组合一致性校验，需服务层验证 SKU 组合属于对应商品。
- `shipment_items` 需要防止累计发货数量超过订单项数量；普通 CHECK 无法跨行保证，需事务服务锁定 order_item 并汇总。
- `order_items.refunded_quantity` 与退款明细金额/数量没有强一致关系；建议退款分摊明细表，且在锁定订单项后累计校验不超额。
- `merchant_orders` 的 item_amount、shipping_amount、merchant_fee、net_amount 与订单项、促销分摊、退款/结算之间需定义可复算口径及快照。
- 订单总单与店铺子单的金额合计约束需要服务层事务校验。
- 学校单校规则需限制配置只允许明德中英文学校，防止误插其他学校；若 school_config 只允许单行，需增加唯一常量约束或单行设计。

### P1：0003 可靠性表仍需加强

- `inventory_reservations` 缺少同一订单项/订单 SKU 活跃预占的唯一/累计规则；需以 SKU 行锁为核心，在事务内检查可售量并更新。
- `outbox_events` 的 UNIQUE(aggregate_type,aggregate_id,event_type,id) 因 id 本身唯一，不能阻止同一业务事件重复插入；应采用稳定 event_key 或业务幂等键唯一约束。
- Outbox 缺少明确 dead-letter/最大重试策略和消费者投递记录；published_at 只能说明发布侧状态，不能证明下游业务完成。
- `refund_freeze_allocations` 与 `settlement_holds` 缺少防止同一待结算金额被重复冻结/重复消费的余额锁定模型。
- `merchant_receivables` 需要还款/核销明细流水，不能仅直接改 outstanding_amount。
- `merchant_withdrawals` 状态字段有 CHECK，但仍需状态迁移约束、审批人不得等于申请人、双人审批门槛、渠道回调幂等和对账流水。

### P2：迁移安全性和可维护性

- `CREATE EXTENSION` 需要执行角色具备权限；部署环境需预先确认 pgcrypto/citext 可用。
- `SET search_path=campus,public` 可能受对象遮蔽和不可信 schema 风险影响；生产建议使用 schema-qualified 对象名并设置受控 search_path。
- 两份迁移不是可重复执行脚本；重复执行预期可能因对象已存在失败。应建立 migration ledger/版本控制机制，不要盲目重跑。
- 0002 声明 PostgreSQL 15+，测试必须固定实际版本并记录扩展版本。
- 删除测试数据库前只保留不含凭据和个人数据的测试日志。

## 3. 下一轮静态审查/测试方案

### A. 语法和迁移测试（隔离库恢复后才执行）
1. 记录 server_version、current_user、current_database、search_path、扩展版本。
2. 在空库依次执行 0002、0003，启用 `ON_ERROR_STOP=1`，保存退出码。
3. 查询 pg_trigger、pg_proc、pg_constraint、pg_indexes 核实对象定义。
4. 在事务内测试借贷分录的 INSERT、UPDATE、DELETE、entry_id 移动、posted/draft 往返、空分录、删除分录等边界。
5. 每个失败用例验证事务回滚，不留下部分账务记录。

### B. 并发和服务层测试
1. 同 SKU 两个并发下单，库存不足时最多一个成功。
2. 同一幂等键重复支付/退款/提现请求，必须只产生一次资金效果。
3. 同一退款重复回调、乱序回调、超时重试。
4. 多个结算/退款事务竞争同一商家待结算余额，不得超额冻结或支付。
5. Outbox 多 worker 并发领取、租约过期、重投、消费者重复消费。
6. 发货累计数量、退款累计数量均不得超过订单项数量。
7. 认证验证码两分钟过期、错误次数限制、发送限流、新设备验证、会话轮换和撤销。

### C. 验收门槛
- SQL parser/迁移：0002、0003 在规定 PostgreSQL 版本空库执行成功。
- 账务不变量：所有成功过账分录借贷相等且非零；非法变更回滚。
- 并发不变量：库存、退款、结算、提现无超卖、超退、超付。
- 权限不变量：业务运行角色不能直接篡改账本和审批记录。
- 可追溯：关键状态迁移、资金动作、后台权限操作均有审计记录。
- 未完成任一门槛，不得标记为数据库验收通过或合并生产。

## 4. 参考资料

- PostgreSQL 官方 CREATE TRIGGER 文档：https://www.postgresql.org/docs/16/sql-createtrigger.html
