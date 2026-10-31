# PostgreSQL 静态审查补充记录 v1.2

> 本轮仅修改 SQL 草案并做文本级复核。未连接 PostgreSQL、未运行 parser/迁移/并发测试；不能视为数据库验证通过。

## 本轮修复

1. `0002`：`journal_entries.status` 默认值由 `posted` 改为 `draft`，并限制为 `draft/posted`。新分录必须先写入借贷明细，再显式过账。
2. `0003`：重写 `assert_journal_entry_balanced()`，按 `TG_OP` 显式分支读取 OLD/NEW，避免在 INSERT/DELETE 路径混合引用不存在的触发器记录；UPDATE 移动明细时检查旧、新两个 entry。
3. `0003`：延迟过账校验不再使用事件快照的 `NEW.status` 决定是否校验，而是在触发器执行时重新读取该分录当前状态，只校验事务最终仍为 posted 的分录。
4. `0003`：增加 journal entry / journal line 修改保护。已过账分录及其明细不可更新或删除；纠错应通过新建冲销分录完成。draft 分录可在过账前写入明细。
5. `0003`：将 outbox 原有无效唯一约束替换为必填唯一 `event_key`。生产者必须对同一业务事件重试复用相同 key，不能每次重试生成新 key。

## 仍未解决/需谨慎

- 当前数据库结构没有定义专用 posting 函数、角色 GRANT/REVOKE、冲销分录关联字段及审计流水；触发器保护不等于完整权限模型。
- 过账和明细写入并发仍需在真实 PostgreSQL 中做多会话压力测试；应用必须通过受控事务流程操作账本。
- outbox 的 `event_key` 语义由业务生产者负责，需为支付成功、退款成功、订单状态变更等事件分别定义稳定键及消费者幂等策略。
- `journal_entries` 的状态 CHECK 目前只限制取值，状态迁移合法性由触发器和权限边界共同约束；后续还需补齐不可逆状态机和冲销关系。
- 本轮没有修复库存预占、退款累计、结算冻结重复占用、提现审批双人复核等其他 P1 项。

## 本轮文本级核对

- 已检查 0002 的 journal_entries 默认状态定义。
- 已检查 0003 outbox_events 字段逗号/表定义尾部。
- 已检查新触发器函数显式分支、最终状态查询和 posted 行保护的文本结构。
- 未执行 PostgreSQL SQL parser；未验证触发器创建语法和运行行为。

## 下一步隔离数据库测试重点

1. 空库执行 0002、0003，确认完整迁移成功。
2. draft 分录插入借贷明细后过账成功；借贷不平、空分录过账必须失败。
3. 同一事务 posted 后再改 draft，提交时按最终 draft 状态处理；posted 后禁止改回 draft。
4. posted entry 的 UPDATE/DELETE、其 journal_lines 的 INSERT/UPDATE/DELETE 均必须失败。
5. UPDATE journal_lines.entry_id 时，旧、新 entry 的平衡约束均生效。
6. 两个会话并发操作同一 entry，验证不会出现借贷不平仍成功提交。
7. 相同 event_key 重复插入必须被唯一约束拒绝；不同业务事件使用不同稳定 key。
