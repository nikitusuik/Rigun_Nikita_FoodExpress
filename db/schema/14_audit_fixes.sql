-- FOOD-101, 102, 103, 105: audit corrections E03-E11,E15,E18-E19.
-- Apply AFTER 01..13 files on a fresh database, or once on the current database.
-- psql -v ON_ERROR_STOP=1 -1 -f db/schema/14_audit_fixes.sql

-- Fix physical duplicates from old generator. Stable UUID suffix only for duplicates.
WITH ranked AS (
  SELECT address_id, row_number() OVER (
    PARTITION BY lower(btrim(street)),lower(btrim(house_number)),lower(btrim(coalesce(apartment_office,'')))
    ORDER BY address_id) AS rn
  FROM rigun_food.address
)
UPDATE rigun_food.address a
SET street = left(a.street, 125) || ' ' || left(a.address_id::text, 12)
FROM ranked x WHERE x.address_id=a.address_id AND x.rn>1;

CREATE UNIQUE INDEX IF NOT EXISTS address_physical_unique
ON rigun_food.address (
    lower(btrim(street)),lower(btrim(house_number)),lower(btrim(coalesce(apartment_office,'')))
);

-- Require hexadecimal MD5 representation.
ALTER TABLE rigun_food.client
DROP CONSTRAINT IF EXISTS client_password_hex;
ALTER TABLE rigun_food.client
ADD CONSTRAINT client_password_hex CHECK (password ~ '^[0-9a-f]{32}$');

-- Each existing order gets one successful payment where missing.
WITH candidates AS (
    SELECT DISTINCT ON (p.order_id) p.payment_id
    FROM rigun_food.payment p
    WHERE NOT EXISTS (
      SELECT 1 FROM rigun_food.payment x
      WHERE x.order_id=p.order_id AND x.status='успех'
    )
    ORDER BY p.order_id,p.transaction_timestamp DESC,p.payment_id
)
UPDATE rigun_food.payment p SET status='успех'
FROM candidates c WHERE p.payment_id=c.payment_id;

-- Disallow amount changes that invalidate existing payments;
-- reject inconsistent manual pay_status changes.
CREATE OR REPLACE FUNCTION rigun_food.guard_order_finance()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE expected rigun_food.order_payment_status;
BEGIN
    IF NEW.total_amount IS DISTINCT FROM OLD.total_amount
       AND EXISTS (SELECT 1 FROM rigun_food.payment p
                   WHERE p.order_id=NEW.order_id
                     AND p.amount IS DISTINCT FROM NEW.total_amount)
    THEN
      RAISE EXCEPTION 'Нельзя менять сумму заказа, не согласовав платежи';
    END IF;
    IF NEW.pay_status IS DISTINCT FROM OLD.pay_status THEN
      SELECT CASE
        WHEN count(*) FILTER (WHERE status='успех')>0 THEN 'оплачен'
        WHEN count(*) FILTER (WHERE status='в_обработке')>0 THEN 'ожидает'
        WHEN count(*)>0 THEN 'ошибка' ELSE 'ожидает'
        END::rigun_food.order_payment_status INTO expected
      FROM rigun_food.payment WHERE order_id=NEW.order_id;
      IF NEW.pay_status IS DISTINCT FROM expected THEN
         RAISE EXCEPTION 'Статус оплаты заказа противоречит платежам';
      END IF;
    END IF;
    RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS guard_order_finance_trigger ON rigun_food."order";
CREATE TRIGGER guard_order_finance_trigger
BEFORE UPDATE OF total_amount,pay_status ON rigun_food."order"
FOR EACH ROW EXECUTE FUNCTION rigun_food.guard_order_finance();

-- Serialize deletion/modification of positions per order; safeguard existing reviews.
CREATE OR REPLACE FUNCTION rigun_food.guard_item_links()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE x uuid;
BEGIN
    -- Shared lock resource for concurrent removals (both must lock same order).
    IF TG_OP IN ('DELETE','UPDATE') THEN
      PERFORM 1 FROM rigun_food."order"
      WHERE order_id=OLD.order_id FOR UPDATE;
      IF (TG_OP='DELETE' OR NEW.product_id IS DISTINCT FROM OLD.product_id
          OR NEW.order_id IS DISTINCT FROM OLD.order_id)
         AND EXISTS (
           SELECT 1 FROM rigun_food.review
           WHERE order_id=OLD.order_id AND entity_type='блюдо'
             AND entity_id=OLD.product_id)
      THEN
        RAISE EXCEPTION 'Нельзя удалить позицию, на которую есть отзыв';
      END IF;
    END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS guard_item_links_trigger ON rigun_food.order_structure;
CREATE TRIGGER guard_item_links_trigger
BEFORE DELETE OR UPDATE ON rigun_food.order_structure
FOR EACH ROW EXECUTE FUNCTION rigun_food.guard_item_links();

CREATE OR REPLACE FUNCTION rigun_food.guard_delete_reviewed_object()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
    IF TG_ARGV[0]='блюдо' THEN
      v_id:=OLD.product_id;
    ELSE
      v_id:=OLD.restaurant_id;
    END IF;
    IF EXISTS (SELECT 1 FROM rigun_food.review r
               WHERE r.entity_type=TG_ARGV[0]::rigun_food.review_entity_type
                 AND r.entity_id=v_id)
    THEN RAISE EXCEPTION 'Нельзя удалить объект с отзывами'; END IF;
    RETURN OLD;
END; $$;
DROP TRIGGER IF EXISTS guard_reviewed_product ON rigun_food.product;
CREATE TRIGGER guard_reviewed_product BEFORE DELETE ON rigun_food.product
FOR EACH ROW EXECUTE FUNCTION rigun_food.guard_delete_reviewed_object('блюдо');
DROP TRIGGER IF EXISTS guard_reviewed_restaurant ON rigun_food.restaurant;
CREATE TRIGGER guard_reviewed_restaurant BEFORE DELETE ON rigun_food.restaurant
FOR EACH ROW EXECUTE FUNCTION rigun_food.guard_delete_reviewed_object('ресторан');

-- Serialize review modifications on the rated parent BEFORE write;
-- subsequent AFTER-trigger AVG sees earlier committed reviewer.
CREATE OR REPLACE FUNCTION rigun_food.lock_review_targets()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE target record;
BEGIN
    IF TG_OP='INSERT' THEN
      FOR target IN SELECT NEW.entity_type AS typ,NEW.entity_id AS id LOOP
        IF target.typ='блюдо' THEN
          PERFORM 1 FROM rigun_food.product WHERE product_id=target.id FOR UPDATE;
        ELSIF target.typ='ресторан' THEN
          PERFORM 1 FROM rigun_food.restaurant WHERE restaurant_id=target.id FOR UPDATE;
        END IF;
      END LOOP;
    ELSIF TG_OP='DELETE' THEN
      FOR target IN SELECT OLD.entity_type AS typ,OLD.entity_id AS id LOOP
        IF target.typ='блюдо' THEN
          PERFORM 1 FROM rigun_food.product WHERE product_id=target.id FOR UPDATE;
        ELSIF target.typ='ресторан' THEN
          PERFORM 1 FROM rigun_food.restaurant WHERE restaurant_id=target.id FOR UPDATE;
        END IF;
      END LOOP;
    ELSE
      FOR target IN
        SELECT DISTINCT typ,id FROM (
          SELECT OLD.entity_type AS typ, OLD.entity_id AS id
          UNION ALL SELECT NEW.entity_type,NEW.entity_id
        ) x WHERE typ IN ('блюдо','ресторан') ORDER BY id,typ
    LOOP
      IF target.typ='блюдо' THEN
        PERFORM 1 FROM rigun_food.product WHERE product_id=target.id FOR UPDATE;
      ELSE
        PERFORM 1 FROM rigun_food.restaurant WHERE restaurant_id=target.id FOR UPDATE;
      END IF;
    END LOOP;
    END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS lock_review_targets_trigger ON rigun_food.review;
CREATE TRIGGER lock_review_targets_trigger
BEFORE INSERT OR UPDATE OR DELETE ON rigun_food.review
FOR EACH ROW EXECUTE FUNCTION rigun_food.lock_review_targets();

-- Prevent explicit TRUNCATE of items while orders exist, bypassing row triggers.
CREATE OR REPLACE FUNCTION rigun_food.guard_truncate_items()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM rigun_food."order") THEN
     RAISE EXCEPTION 'Нельзя очищать позиции через TRUNCATE при существующих заказах';
  END IF;
  RETURN NULL;
END; $$;
DROP TRIGGER IF EXISTS guard_truncate_items_trigger ON rigun_food.order_structure;
CREATE TRIGGER guard_truncate_items_trigger BEFORE TRUNCATE
ON rigun_food.order_structure FOR EACH STATEMENT
EXECUTE FUNCTION rigun_food.guard_truncate_items();
