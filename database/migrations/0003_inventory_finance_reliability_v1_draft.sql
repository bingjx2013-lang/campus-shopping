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

-- Atomic inventory reservation API. Treat skus.stock_on_hand as AVAILABLE stock.
-- A failed insert/unique-key race rolls back the stock decrement with the surrounding transaction.
CREATE OR REPLACE FUNCTION reserve_sku_inventory(
 p_sku_id uuid,
 p_order_id uuid,
 p_order_item_id uuid,
 p_quantity bigint,
 p_expires_at timestamptz,
 p_idempotency_key text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
 existing inventory_reservations%ROWTYPE;
 new_id uuid := gen_random_uuid();
 stock_mode_value text;
BEGIN
 IF p_quantity IS NULL OR p_quantity<=0 OR p_expires_at<=now()
    OR p_idempotency_key IS NULL OR length(trim(p_idempotency_key))=0 THEN
   RAISE EXCEPTION 'invalid inventory reservation input' USING ERRCODE='22023';
 END IF;
 SELECT * INTO existing FROM inventory_reservations WHERE idempotency_key=p_idempotency_key;
 IF FOUND THEN
   IF existing.sku_id IS DISTINCT FROM p_sku_id
      OR existing.order_id IS DISTINCT FROM p_order_id
      OR existing.order_item_id IS DISTINCT FROM p_order_item_id
      OR existing.quantity IS DISTINCT FROM p_quantity
      OR existing.expires_at IS DISTINCT FROM p_expires_at THEN
     RAISE EXCEPTION 'idempotency key reused with different reservation data' USING ERRCODE='23505';
   END IF;
   RETURN existing.id;
 END IF;
 SELECT stock_mode INTO stock_mode_value FROM skus WHERE id=p_sku_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'SKU not found' USING ERRCODE='23503'; END IF;
 -- Recheck after acquiring the SKU lock: a concurrent request with the same key may
 -- have completed while this transaction waited for the lock.
 SELECT * INTO existing FROM inventory_reservations WHERE idempotency_key=p_idempotency_key;
 IF FOUND THEN
   IF existing.sku_id IS DISTINCT FROM p_sku_id
      OR existing.order_id IS DISTINCT FROM p_order_id
      OR existing.order_item_id IS DISTINCT FROM p_order_item_id
      OR existing.quantity IS DISTINCT FROM p_quantity
      OR existing.expires_at IS DISTINCT FROM p_expires_at THEN
     RAISE EXCEPTION 'idempotency key reused with different reservation data' USING ERRCODE='23505';
   END IF;
   RETURN existing.id;
 END IF;
 IF p_order_item_id IS NOT NULL AND NOT EXISTS (
   SELECT 1
   FROM order_items oi
   JOIN merchant_orders mo ON mo.id=oi.merchant_order_id
   WHERE oi.id=p_order_item_id AND oi.sku_id=p_sku_id AND mo.order_id=p_order_id
 ) THEN
   RAISE EXCEPTION 'order item does not belong to order or SKU' USING ERRCODE='23503';
 END IF;
 IF stock_mode_value='tracked' THEN
   UPDATE skus SET stock_on_hand=stock_on_hand-p_quantity
    WHERE id=p_sku_id AND stock_on_hand>=p_quantity;
   IF NOT FOUND THEN RAISE EXCEPTION 'insufficient inventory' USING ERRCODE='23514'; END IF;
 END IF;
 INSERT INTO inventory_reservations(id,sku_id,order_item_id,order_id,quantity,expires_at,idempotency_key)
 VALUES(new_id,p_sku_id,p_order_item_id,p_order_id,p_quantity,p_expires_at,p_idempotency_key);
 RETURN new_id;
END $$;

-- Release is idempotent. The row lock ensures only one concurrent caller restores stock.
CREATE OR REPLACE FUNCTION release_sku_inventory(p_reservation_id uuid)
RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE r inventory_reservations%ROWTYPE;
BEGIN
 SELECT * INTO r FROM inventory_reservations WHERE id=p_reservation_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'reservation not found' USING ERRCODE='P0002'; END IF;
 IF r.status<>'reserved' THEN RETURN false; END IF;
 UPDATE inventory_reservations SET status='released',resolved_at=now() WHERE id=r.id;
 UPDATE skus SET stock_on_hand=stock_on_hand+r.quantity
  WHERE id=r.sku_id AND stock_mode='tracked';
 RETURN true;
END $$;

-- Consume finalizes a reservation after successful payment; stock was already deducted at reserve time.
CREATE OR REPLACE FUNCTION consume_sku_inventory(p_reservation_id uuid)
RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE r inventory_reservations%ROWTYPE;
BEGIN
 SELECT * INTO r FROM inventory_reservations WHERE id=p_reservation_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'reservation not found' USING ERRCODE='P0002'; END IF;
 IF r.status='consumed' THEN RETURN false; END IF;
 IF r.status<>'reserved' OR r.expires_at<=now() THEN
   RAISE EXCEPTION 'reservation is not consumable' USING ERRCODE='23514';
 END IF;
 UPDATE inventory_reservations SET status='consumed',resolved_at=now() WHERE id=r.id;
 RETURN true;
END $$;

-- Expire reservations in bounded batches. SKIP LOCKED allows multiple workers safely.
-- Stock is restored in the same transaction as the state transition.
CREATE OR REPLACE FUNCTION expire_sku_inventory_reservations(p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql AS $expiry$
DECLARE
 r inventory_reservations%ROWTYPE;
 expired_count integer := 0;
BEGIN
 IF p_limit IS NULL OR p_limit<1 OR p_limit>10000 THEN
   RAISE EXCEPTION 'invalid expiry batch size' USING ERRCODE='22023';
 END IF;
 FOR r IN
   SELECT * FROM inventory_reservations
    WHERE status='reserved' AND expires_at<=now()
    ORDER BY expires_at,id
    FOR UPDATE SKIP LOCKED
    LIMIT p_limit
 LOOP
   UPDATE inventory_reservations
      SET status='expired',resolved_at=now()
    WHERE id=r.id AND status='reserved';
   IF FOUND THEN
     UPDATE skus SET stock_on_hand=stock_on_hand+r.quantity
      WHERE id=r.sku_id AND stock_mode='tracked';
     expired_count := expired_count+1;
   END IF;
 END LOOP;
 RETURN expired_count;
END $expiry$;

-- Durable transactional outbox. event_key is a stable business idempotency key supplied by the
-- producer; do not derive it from the random event row id.
CREATE TABLE outbox_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 aggregate_type text NOT NULL,
 aggregate_id uuid NOT NULL,
 event_type text NOT NULL,
 event_key text NOT NULL UNIQUE,
 payload jsonb NOT NULL,
 occurred_at timestamptz NOT NULL DEFAULT now(),
 available_at timestamptz NOT NULL DEFAULT now(),
 attempts int NOT NULL DEFAULT 0 CHECK(attempts>=0),
 locked_until timestamptz,
 published_at timestamptz,
 last_error text
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
-- Ledger rules:
-- 1) Entries are created as draft, populated, then posted explicitly.
-- 2) Posted entries/lines are immutable; corrections use reversing entries.
-- 3) The deferred checks read the transaction's final row state, not stale event NEW values.
CREATE OR REPLACE FUNCTION guard_journal_entry_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN
   IF OLD.status='posted' THEN
     RAISE EXCEPTION 'posted journal entry % is immutable; create a reversing entry',OLD.id
       USING ERRCODE='23514';
   END IF;
   RETURN OLD;
 END IF;
 IF OLD.status='posted' THEN
   RAISE EXCEPTION 'posted journal entry % is immutable; create a reversing entry',OLD.id
     USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER trg_guard_journal_entry_mutation
BEFORE UPDATE OR DELETE ON journal_entries
FOR EACH ROW EXECUTE FUNCTION guard_journal_entry_mutation();

CREATE OR REPLACE FUNCTION guard_journal_line_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE old_status text; new_status text;
BEGIN
 IF TG_OP IN ('UPDATE','DELETE') THEN
   SELECT status INTO old_status FROM journal_entries WHERE id=OLD.entry_id FOR UPDATE;
   IF old_status='posted' THEN
     RAISE EXCEPTION 'journal lines of posted entry % are immutable',OLD.entry_id
       USING ERRCODE='23514';
   END IF;
 END IF;
 IF TG_OP IN ('INSERT','UPDATE') THEN
   SELECT status INTO new_status FROM journal_entries WHERE id=NEW.entry_id FOR UPDATE;
   IF new_status='posted' THEN
     RAISE EXCEPTION 'cannot add or move lines into posted entry %',NEW.entry_id
       USING ERRCODE='23514';
   END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER trg_guard_journal_line_mutation
BEFORE INSERT OR UPDATE OR DELETE ON journal_lines
FOR EACH ROW EXECUTE FUNCTION guard_journal_line_mutation();

CREATE OR REPLACE FUNCTION assert_journal_entry_balanced() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
 check_entry uuid;
 old_entry uuid;
 new_entry uuid;
 debit_total numeric(18,2);
 credit_total numeric(18,2);
 entry_status text;
BEGIN
 -- Read only the transition records that exist for this operation.
 IF TG_OP='INSERT' THEN
   new_entry := NEW.entry_id;
 ELSIF TG_OP='DELETE' THEN
   old_entry := OLD.entry_id;
 ELSIF TG_OP='UPDATE' THEN
   old_entry := OLD.entry_id;
   new_entry := NEW.entry_id;
 ELSE
   RAISE EXCEPTION 'unsupported trigger operation %',TG_OP;
 END IF;

 FOR check_entry IN
   SELECT DISTINCT v.entry_id
   FROM (VALUES (old_entry),(new_entry)) AS v(entry_id)
   WHERE v.entry_id IS NOT NULL
 LOOP
   SELECT je.status INTO entry_status
   FROM journal_entries AS je WHERE je.id=check_entry;
   IF FOUND AND entry_status='posted' THEN
     SELECT COALESCE(sum(jl.debit),0),COALESCE(sum(jl.credit),0)
       INTO debit_total,credit_total
     FROM journal_lines AS jl WHERE jl.entry_id=check_entry;
     IF debit_total=0 OR debit_total<>credit_total THEN
       RAISE EXCEPTION 'journal entry % is not balanced (debit %, credit %)',
         check_entry,debit_total,credit_total USING ERRCODE='23514';
     END IF;
   END IF;
 END LOOP;
 RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER trg_journal_lines_balanced
AFTER INSERT OR UPDATE OR DELETE ON journal_lines
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION assert_journal_entry_balanced();

CREATE OR REPLACE FUNCTION assert_posted_entry_balanced() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
 current_status text;
 debit_total numeric(18,2);
 credit_total numeric(18,2);
BEGIN
 -- Deferred trigger NEW may represent an earlier event in this transaction.
 SELECT status INTO current_status FROM journal_entries WHERE id=NEW.id;
 IF FOUND AND current_status='posted' THEN
   SELECT COALESCE(sum(debit),0),COALESCE(sum(credit),0)
     INTO debit_total,credit_total
   FROM journal_lines WHERE entry_id=NEW.id;
   IF debit_total=0 OR debit_total<>credit_total THEN
     RAISE EXCEPTION 'cannot commit unbalanced journal entry % (debit %, credit %)',
       NEW.id,debit_total,credit_total USING ERRCODE='23514';
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

-- IMPORTANT: this migration remains a draft and has not been executed.
-- Posting must occur through a narrowly privileged transactional service/function. The row guards
-- enforce immutability, but production role grants, entry-level serialization, audit logging,
-- outbox leasing/retries, inventory arithmetic, and payout reconciliation remain to be implemented.
-- event_key must be generated deterministically by each business producer and reused on retries.
COMMIT;
