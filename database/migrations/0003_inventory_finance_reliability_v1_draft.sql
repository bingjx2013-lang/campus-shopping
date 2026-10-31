-- Campus Shopping reliability extensions v1.0 (DRAFT; NOT EXECUTED)
-- Depends on 0002_campus_shopping_full_schema_v1_draft.sql and schema campus.
-- PostgreSQL 15+. Apply only in an isolated disposable database after review.
BEGIN;
SET search_path=campus,public;

-- Inventory reservations: reserve first, then consume on successful order confirmation;
-- release on cancellation/expiry. All state transitions must be performed by transactional services.
CREATE TABLE inventory_reservations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 sku_id uuid NOT NULL REFERENCES skus(id),
 order_item_id uuid REFERENCES order_items(id),
 order_id uuid NOT NULL REFERENCES orders(id),
 quantity bigint NOT NULL CHECK(quantity>0),
 status text NOT NULL DEFAULT 'reserved' CHECK(status IN('reserved','consumed','released','expired')),
 expires_at timestamptz NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 resolved_at timestamptz,
 idempotency_key text NOT NULL UNIQUE,
 CHECK ((status='reserved' AND resolved_at IS NULL) OR (status<>'reserved' AND resolved_at IS NOT NULL))
);
CREATE INDEX idx_inventory_reservations_live ON inventory_reservations(sku_id,expires_at) WHERE status='reserved';
CREATE INDEX idx_inventory_reservations_order ON inventory_reservations(order_id,status);

-- Durable transactional outbox. Publisher retries until published_at is set; consumers deduplicate event_id.
CREATE TABLE outbox_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 aggregate_type text NOT NULL,
 aggregate_id uuid NOT NULL,
 event_type text NOT NULL,
 payload jsonb NOT NULL,
 occurred_at timestamptz NOT NULL DEFAULT now(),
 available_at timestamptz NOT NULL DEFAULT now(),
 attempts int NOT NULL DEFAULT 0 CHECK(attempts>=0),
 locked_until timestamptz,
 published_at timestamptz,
 last_error text,
 UNIQUE(aggregate_type,aggregate_id,event_type,id)
);
CREATE INDEX idx_outbox_pending ON outbox_events(available_at,occurred_at) WHERE published_at IS NULL;

-- Refund allocation freezes the merchant's unsettled proceeds per refund.
CREATE TABLE refund_freeze_allocations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 refund_id uuid NOT NULL REFERENCES refunds(id),
 merchant_order_id uuid NOT NULL REFERENCES merchant_orders(id),
 amount numeric(14,2) NOT NULL CHECK(amount>0),
 status text NOT NULL DEFAULT 'frozen' CHECK(status IN('frozen','consumed','released','shortfall')),
 created_at timestamptz NOT NULL DEFAULT now(),
 resolved_at timestamptz,
 UNIQUE(refund_id,merchant_order_id)
);
CREATE TABLE merchant_receivables (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 merchant_id uuid NOT NULL REFERENCES merchants(id),
 source_refund_id uuid REFERENCES refunds(id),
 original_amount numeric(14,2) NOT NULL CHECK(original_amount>0),
 outstanding_amount numeric(14,2) NOT NULL CHECK(outstanding_amount>=0 AND outstanding_amount<=original_amount),
 status text NOT NULL DEFAULT 'open' CHECK(status IN('open','partially_repaid','settled','written_off')),
 created_at timestamptz NOT NULL DEFAULT now(),
 settled_at timestamptz
);
CREATE INDEX idx_merchant_receivables_open ON merchant_receivables(merchant_id,status) WHERE outstanding_amount>0;

-- Settlement holds prevent disputed/refund-exposed proceeds from being paid out.
CREATE TABLE settlement_holds (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 merchant_id uuid NOT NULL REFERENCES merchants(id),
 merchant_order_id uuid REFERENCES merchant_orders(id),
 refund_id uuid REFERENCES refunds(id),
 amount numeric(14,2) NOT NULL CHECK(amount>0),
 reason text NOT NULL,
 status text NOT NULL DEFAULT 'active' CHECK(status IN('active','released','consumed')),
 created_at timestamptz NOT NULL DEFAULT now(),
 resolved_at timestamptz,
 CHECK(merchant_order_id IS NOT NULL OR refund_id IS NOT NULL)
);
CREATE INDEX idx_settlement_holds_active ON settlement_holds(merchant_id) WHERE status='active';

-- Merchant withdrawal requests. External payout provider references are opaque; never store bank secrets here.
CREATE TABLE merchant_withdrawals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 merchant_id uuid NOT NULL REFERENCES merchants(id),
 wallet_id uuid NOT NULL REFERENCES wallets(id),
 amount numeric(14,2) NOT NULL CHECK(amount>0),
 fee_amount numeric(14,2) NOT NULL DEFAULT 0 CHECK(fee_amount>=0),
 status text NOT NULL DEFAULT 'requested' CHECK(status IN('requested','reviewing','approved','processing','paid','rejected','failed','cancelled')),
 payout_provider text,
 provider_reference text,
 idempotency_key text NOT NULL UNIQUE,
 requested_at timestamptz NOT NULL DEFAULT now(),
 reviewed_by uuid REFERENCES users(id),
 reviewed_at timestamptz,
 completed_at timestamptz,
 rejection_reason text
);
CREATE INDEX idx_merchant_withdrawals_review ON merchant_withdrawals(status,requested_at);

-- Explicit journal-entry balance validation. This deferred constraint trigger checks the final
-- transaction state, allowing debit and credit lines to be inserted in separate statements.
CREATE OR REPLACE FUNCTION assert_journal_entry_balanced() RETURNS trigger
LANGUAGE plpgsql AS $
DECLARE
 target_entry uuid;
 check_entry uuid;
 debit_total numeric(18,2);
 credit_total numeric(18,2);
 entry_status text;
BEGIN
 -- On UPDATE, validate both sides if a journal line moves between entries.
 IF TG_OP = 'DELETE' THEN
   target_entry := OLD.entry_id;
 ELSE
   target_entry := NEW.entry_id;
 END IF;

 FOR check_entry IN
   SELECT DISTINCT x
   FROM unnest(ARRAY[
     CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN OLD.entry_id ELSE NULL END,
     CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN NEW.entry_id ELSE NULL END
   ]) AS t(x)
   WHERE x IS NOT NULL
 LOOP
   SELECT status INTO entry_status FROM journal_entries WHERE id=check_entry;
   IF FOUND AND entry_status='posted' THEN
     SELECT COALESCE(sum(debit),0), COALESCE(sum(credit),0)
       INTO debit_total,credit_total FROM journal_lines WHERE entry_id=check_entry;
     IF debit_total=0 OR debit_total<>credit_total THEN
       RAISE EXCEPTION 'journal entry % is not balanced (debit %, credit %)',check_entry,debit_total,credit_total
         USING ERRCODE='23514';
     END IF;
   END IF;
 END LOOP;
 RETURN NULL;
END $;
CREATE CONSTRAINT TRIGGER trg_journal_lines_balanced
AFTER INSERT OR UPDATE OR DELETE ON journal_lines
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION assert_journal_entry_balanced();

CREATE OR REPLACE FUNCTION assert_posted_entry_balanced() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE debit_total numeric(18,2); credit_total numeric(18,2);
BEGIN
 IF NEW.status='posted' AND (TG_OP='INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
   SELECT COALESCE(sum(debit),0),COALESCE(sum(credit),0)
     INTO debit_total,credit_total FROM journal_lines WHERE entry_id=NEW.id;
   IF debit_total=0 OR debit_total<>credit_total THEN
     RAISE EXCEPTION 'cannot post unbalanced journal entry % (debit %, credit %)',NEW.id,debit_total,credit_total
       USING ERRCODE='23514';
   END IF;
 END IF;
 RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER trg_journal_entry_posted_balanced
AFTER INSERT OR UPDATE OF status ON journal_entries
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION assert_posted_entry_balanced();

-- Operational guardrails: indexes for expiry sweeps and idempotent lookup.
CREATE INDEX idx_auth_codes_expiry ON verification_codes(expires_at) WHERE consumed_at IS NULL;
CREATE INDEX idx_sessions_active_expiry ON auth_sessions(expires_at) WHERE revoked_at IS NULL;
CREATE INDEX idx_refunds_case_status ON refunds(case_id,status);

-- IMPORTANT: this migration defines persistence structures and a ledger invariant only.
-- Application code must still implement row locking, stock arithmetic, reserve/consume/release
-- state transitions, payout provider reconciliation, outbox leasing/retries, and idempotent APIs.
-- The trigger is a safety net, not a substitute for a controlled posting function/permissions.
COMMIT;
