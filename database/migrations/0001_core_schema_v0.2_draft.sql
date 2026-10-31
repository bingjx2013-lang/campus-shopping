-- 校园购 PostgreSQL 核心结构草案 V0.2
-- 设计骨架，非生产迁移。需先与完整 V0.1 schema 对齐。
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS finance_accounts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 account_code varchar(40) NOT NULL UNIQUE,
 account_name varchar(120) NOT NULL,
 account_type varchar(16) NOT NULL CHECK (account_type IN ('asset','liability','equity','revenue','expense')),
 currency char(3) NOT NULL DEFAULT 'CNY',
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS accounting_entries (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 entry_no varchar(48) NOT NULL UNIQUE,
 business_type varchar(40) NOT NULL,
 business_id uuid NOT NULL,
 idempotency_key varchar(120) NOT NULL UNIQUE,
 status varchar(16) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','posted','reversed')),
 description text,
 occurred_at timestamptz NOT NULL,
 posted_at timestamptz,
 reversed_entry_id uuid REFERENCES accounting_entries(id)
);
CREATE TABLE IF NOT EXISTS accounting_entry_lines (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 entry_id uuid NOT NULL REFERENCES accounting_entries(id),
 account_id uuid NOT NULL REFERENCES finance_accounts(id),
 side char(1) NOT NULL CHECK (side IN ('D','C')),
 amount numeric(16,2) NOT NULL CHECK (amount > 0),
 currency char(3) NOT NULL DEFAULT 'CNY',
 memo text
);
CREATE INDEX IF NOT EXISTS idx_accounting_lines_entry ON accounting_entry_lines(entry_id);

CREATE TABLE IF NOT EXISTS platform_policy_versions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 policy_key varchar(80) NOT NULL,
 version integer NOT NULL CHECK (version > 0),
 policy_json jsonb NOT NULL,
 effective_from timestamptz NOT NULL,
 effective_to timestamptz,
 created_by uuid,
 approved_by uuid,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(policy_key,version),
 CHECK (effective_to IS NULL OR effective_to > effective_from)
);
CREATE TABLE IF NOT EXISTS founder_authorizations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL,
 authorization_status varchar(16) NOT NULL CHECK (authorization_status IN ('active','suspended','revoked')),
 reason text NOT NULL,
 mfa_required boolean NOT NULL DEFAULT true,
 granted_at timestamptz NOT NULL DEFAULT now(),
 revoked_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_active_founder_user ON founder_authorizations(user_id) WHERE authorization_status='active';
CREATE TABLE IF NOT EXISTS admin_sensitive_access_logs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 admin_user_id uuid NOT NULL,
 subject_user_id uuid,
 data_category varchar(40) NOT NULL,
 purpose text NOT NULL,
 approved_by uuid,
 accessed_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS file_access_permissions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 object_key text NOT NULL,
 granted_to_user_id uuid,
 granted_to_role varchar(40),
 purpose varchar(80) NOT NULL,
 expires_at timestamptz,
 revoked_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK (granted_to_user_id IS NOT NULL OR granted_to_role IS NOT NULL)
);
CREATE TABLE IF NOT EXISTS file_access_logs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 object_key text NOT NULL,
 actor_user_id uuid,
 action varchar(20) NOT NULL CHECK (action IN ('view','download','upload','delete_request')),
 purpose text,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS personal_data_export_jobs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL,
 status varchar(20) NOT NULL DEFAULT 'requested',
 requested_at timestamptz NOT NULL DEFAULT now(),
 completed_at timestamptz,
 expires_at timestamptz,
 object_key text
);
CREATE TABLE IF NOT EXISTS account_deletion_requests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL,
 status varchar(20) NOT NULL DEFAULT 'requested',
 retention_exceptions jsonb NOT NULL DEFAULT '[]',
 requested_at timestamptz NOT NULL DEFAULT now(),
 completed_at timestamptz
);

-- 待后续迁移补齐：库存预留/流水、订单快照、分批配送、售后退款冻结、商家待结算/应收、
-- 收费与额度规则、通知消息、申诉、紧急操作和完整外键。
-- 正式版必须增加受控过账函数及 DEFERRABLE constraint trigger 校验每笔分录借贷平衡。
ROLLBACK; -- 默认回滚，防止将未验证的草案误留在数据库。
