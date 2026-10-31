#!/usr/bin/env bash
set -euo pipefail

export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
export PGDATABASE="${PGDATABASE:-campus_test}"
: "${PGPASSWORD:=postgres}"
export PGPASSWORD

tmp="$(mktemp -d)"
blocker_pid=""
cleanup() {
  if [[ -n "$blocker_pid" ]]; then kill "$blocker_pid" 2>/dev/null || true; wait "$blocker_pid" 2>/dev/null || true; fi
  rm -rf "$tmp"
}
trap cleanup EXIT

psqlq() { psql -X -v ON_ERROR_STOP=1 -qAt "$@"; }

user_id="$(psqlq -c 'SELECT gen_random_uuid()')"
merchant_id="$(psqlq -c 'SELECT gen_random_uuid()')"
product_id="$(psqlq -c 'SELECT gen_random_uuid()')"
sku_id="$(psqlq -c 'SELECT gen_random_uuid()')"
order_id="$(psqlq -c 'SELECT gen_random_uuid()')"
merchant_order_id="$(psqlq -c 'SELECT gen_random_uuid()')"
item_id="$(psqlq -c 'SELECT gen_random_uuid()')"
merchant_no="CI-$(psqlq -c "SELECT replace(gen_random_uuid()::text,'-','')")"
sku_code="CI-$(psqlq -c "SELECT replace(gen_random_uuid()::text,'-','')")"
order_no="CI-$(psqlq -c "SELECT replace(gen_random_uuid()::text,'-','')")"

psql -X -v ON_ERROR_STOP=1 \
  -v u="$user_id" -v m="$merchant_id" -v p="$product_id" -v s="$sku_id" \
  -v o="$order_id" -v mo="$merchant_order_id" -v oi="$item_id" \
  -v mn="$merchant_no" -v sc="$sku_code" -v on="$order_no" <<'SQL'
SET search_path=campus,public;
INSERT INTO users(id,display_name,user_type,status) VALUES (:'u','Concurrency CI','student','active');
INSERT INTO merchants(id,owner_user_id,merchant_no,name,merchant_type) VALUES (:'m',:'u',:'mn','Concurrency Merchant','general');
INSERT INTO products(id,merchant_id,title) VALUES (:'p',:'m','Concurrency Product');
INSERT INTO skus(id,product_id,sku_code,price,stock_mode,stock_on_hand) VALUES (:'s',:'p',:'sc',1,'tracked',1);
INSERT INTO orders(id,order_no,buyer_user_id,item_amount,discount_amount,shipping_amount,payable_amount) VALUES (:'o',:'on',:'u',1,0,0,1);
INSERT INTO merchant_orders(id,order_id,merchant_id,item_amount,shipping_amount,merchant_fee,net_amount) VALUES (:'mo',:'o',:'m',1,0,0,1);
INSERT INTO order_items(id,merchant_order_id,product_id,sku_id,product_title_snapshot,unit_price,quantity,line_total) VALUES (:'oi',:'mo',:'p',:'s','Concurrency Product',1,1,1);
SQL

run_blocked_race() {
  local label="$1" key1="$2" key2="$3" expected="$4"
  local expiry
  expiry="$(psqlq -c "SELECT (clock_timestamp()+interval '5 minutes')::text")"
  psql -X -v ON_ERROR_STOP=1 -q \
    -v s="$sku_id" -v label="$label" <<'SQL' >"$tmp/blocker.log" 2>&1 &
SET application_name='campus_ci_concurrency_blocker';
BEGIN;
SELECT id FROM campus.skus WHERE id=:'s' FOR UPDATE;
SELECT pg_sleep(2);
COMMIT;
SQL
  blocker_pid=$!
  sleep 0.35
  for n in 1 2; do
    local key
    if [[ "$n" == 1 ]]; then key="$key1"; else key="$key2"; fi
    (
      psql -X -v ON_ERROR_STOP=1 -qAt \
        -v s="$sku_id" -v o="$order_id" -v oi="$item_id" \
        -v expiry="$expiry" -v key="$key" <<'SQL'
SELECT campus.reserve_sku_inventory(:'s'::uuid,:'o'::uuid,:'oi'::uuid,1,:'expiry'::timestamptz,:'key');
SQL
    ) >"$tmp/$label.$n.out" 2>"$tmp/$label.$n.err" &
    eval "pid$n=$!"
  done
  local status1=0 status2=0
  wait "$pid1" || status1=$?
  wait "$pid2" || status2=$?
  wait "$blocker_pid" || true
  blocker_pid=""
  printf '%s %s\n' "$status1" "$status2" >"$tmp/$label.status"
}

run_blocked_race stock-race "ci-stock-race-a-$(psqlq -c 'SELECT gen_random_uuid()')" "ci-stock-race-b-$(psqlq -c 'SELECT gen_random_uuid()')" stock
successes=0
failures=0
for n in 1 2; do
  if [[ ! -s "$tmp/stock-race.$n.err" ]]; then successes=$((successes+1))
  elif grep -qi 'insufficient inventory' "$tmp/stock-race.$n.err"; then failures=$((failures+1))
  else cat "$tmp/stock-race.$n.err" >&2; echo "Unexpected stock-race error" >&2; exit 1
  fi
done
[[ "$successes" -eq 1 && "$failures" -eq 1 ]] || { echo "Expected exactly one stock reservation success and one insufficient-inventory failure" >&2; exit 1; }
[[ "$(psqlq -c "SELECT stock_on_hand FROM campus.skus WHERE id='$sku_id'")" == "0" ]] || { echo "Stock must finish at zero" >&2; exit 1; }
[[ "$(psqlq -c "SELECT count(*) FROM campus.inventory_reservations WHERE sku_id='$sku_id'")" == "1" ]] || { echo "Exactly one reservation must exist after stock race" >&2; exit 1; }

reservation_id="$(psqlq -c "SELECT id FROM campus.inventory_reservations WHERE sku_id='$sku_id'")"
psqlq -c "SELECT campus.release_sku_inventory('$reservation_id'::uuid)" >/dev/null
[[ "$(psqlq -c "SELECT stock_on_hand FROM campus.skus WHERE id='$sku_id'")" == "1" ]] || { echo "Fixture reset did not restore stock" >&2; exit 1; }

same_key="ci-same-key-$(psqlq -c 'SELECT gen_random_uuid()')"
run_blocked_race idempotency-race "$same_key" "$same_key" idempotency
status1="$(awk '{print $1}' "$tmp/idempotency-race.status")"
status2="$(awk '{print $2}' "$tmp/idempotency-race.status")"
[[ "$status1" == "0" && "$status2" == "0" ]] || { cat "$tmp/idempotency-race."*.err >&2; echo "Both same-key requests must succeed" >&2; exit 1; }
r1="$(cat "$tmp/idempotency-race.1.out" | tail -n 1)"
r2="$(cat "$tmp/idempotency-race.2.out" | tail -n 1)"
[[ -n "$r1" && "$r1" == "$r2" ]] || { echo "Concurrent idempotent requests returned different reservation IDs" >&2; exit 1; }
[[ "$(psqlq -c "SELECT stock_on_hand FROM campus.skus WHERE id='$sku_id'")" == "0" ]] || { echo "Idempotent race must decrement stock exactly once" >&2; exit 1; }
[[ "$(psqlq -c "SELECT count(*) FROM campus.inventory_reservations WHERE sku_id='$sku_id'")" == "1" ]] || { echo "Idempotent race must create exactly one reservation" >&2; exit 1; }

echo "PASS: independent PostgreSQL sessions serialize final-unit stock race."
echo "PASS: same idempotency key returns one reservation and decrements stock once."
