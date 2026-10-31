-- Disposable PostgreSQL integration checks for 0003 inventory functions.
BEGIN;
SET search_path=campus,public;
DO $$
DECLARE
 u uuid := gen_random_uuid(); m uuid := gen_random_uuid(); p uuid := gen_random_uuid();
 s uuid := gen_random_uuid(); o uuid := gen_random_uuid(); mo uuid := gen_random_uuid();
 oi uuid := gen_random_uuid(); r uuid; r2 uuid;
BEGIN
 INSERT INTO users(id,display_name,user_type,status) VALUES(u,'Inventory CI','student','active');
 INSERT INTO merchants(id,owner_user_id,merchant_no,name,merchant_type) VALUES(m,u,'CI-'||replace(gen_random_uuid()::text,'-',''),'CI Merchant','general');
 INSERT INTO products(id,merchant_id,title) VALUES(p,m,'CI Product');
 INSERT INTO skus(id,product_id,sku_code,price,stock_mode,stock_on_hand) VALUES(s,p,'CI-'||replace(gen_random_uuid()::text,'-',''),1,'tracked',5);
 INSERT INTO orders(id,order_no,buyer_user_id,item_amount,discount_amount,shipping_amount,payable_amount) VALUES(o,'CI-'||replace(gen_random_uuid()::text,'-',''),u,5,0,0,5);
 INSERT INTO merchant_orders(id,order_id,merchant_id,item_amount,shipping_amount,merchant_fee,net_amount) VALUES(mo,o,m,5,0,0,5);
 INSERT INTO order_items(id,merchant_order_id,product_id,sku_id,product_title_snapshot,unit_price,quantity,line_total) VALUES(oi,mo,p,s,'CI Product',1,5,5);
 r:=reserve_sku_inventory(s,o,oi,3,now()+interval '5 minutes','ci-reserve-'||gen_random_uuid()::text);
 r2:=reserve_sku_inventory(s,o,oi,3,now()+interval '5 minutes',(SELECT idempotency_key FROM inventory_reservations WHERE id=r));
 IF r<>r2 THEN RAISE EXCEPTION 'idempotent reserve did not return same reservation'; END IF;
 IF (SELECT stock_on_hand FROM skus WHERE id=s)<>2 THEN RAISE EXCEPTION 'reserve did not decrement stock'; END IF;
 IF NOT release_sku_inventory(r) THEN RAISE EXCEPTION 'first release should change state'; END IF;
 IF release_sku_inventory(r) THEN RAISE EXCEPTION 'second release must be a no-op'; END IF;
 IF (SELECT stock_on_hand FROM skus WHERE id=s)<>5 THEN RAISE EXCEPTION 'release did not restore stock exactly once'; END IF;
 r:=reserve_sku_inventory(s,o,oi,4,now()+interval '5 minutes','ci-consume-'||gen_random_uuid()::text);
 IF NOT consume_sku_inventory(r) THEN RAISE EXCEPTION 'consume should change state'; END IF;
 IF consume_sku_inventory(r) THEN RAISE EXCEPTION 'second consume must be a no-op'; END IF;
 IF (SELECT stock_on_hand FROM skus WHERE id=s)<>1 THEN RAISE EXCEPTION 'consume must not restore stock'; END IF;
 BEGIN
   PERFORM reserve_sku_inventory(s,o,oi,2,now()+interval '5 minutes','ci-insufficient-'||gen_random_uuid()::text);
   RAISE EXCEPTION 'insufficient stock unexpectedly succeeded';
 EXCEPTION WHEN check_violation THEN NULL;
 END;
 IF (SELECT stock_on_hand FROM skus WHERE id=s)<>1 THEN RAISE EXCEPTION 'failed reserve changed stock'; END IF;
END $$;
ROLLBACK;
