-- FOOD-101: close audit findings E03/E04/E05/E10/E14
-- Apply as one transaction with psql -X -v ON_ERROR_STOP=1 -1 -f ...

-- E04: serialize changes to an order amount and its payment rows.
-- The row lock is taken BEFORE the existing amount check and before writing payment.
CREATE OR REPLACE FUNCTION rigun_food.a_lock_payment_order()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_order_id uuid;
BEGIN
    -- Lock in consistent order to minimize deadlocks when moving a payment.
    FOR v_order_id IN
      SELECT DISTINCT order_id FROM (
          SELECT CASE WHEN TG_OP <> 'INSERT' THEN OLD.order_id END AS order_id
          UNION ALL
          SELECT CASE WHEN TG_OP <> 'DELETE' THEN NEW.order_id END
      ) x WHERE order_id IS NOT NULL ORDER BY order_id
    LOOP
        PERFORM 1 FROM rigun_food."order" o
        WHERE o.order_id = v_order_id FOR UPDATE;
    END LOOP;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS a_lock_payment_order_trigger ON rigun_food.payment;
CREATE TRIGGER a_lock_payment_order_trigger
BEFORE INSERT OR UPDATE ON rigun_food.payment
FOR EACH ROW EXECUTE FUNCTION rigun_food.a_lock_payment_order();

-- E05: serialize creation/change of reviews with removal/change of order items.
-- guard_item_links_trigger already locks the same parent order before item DELETE/UPDATE.
CREATE OR REPLACE FUNCTION rigun_food.a_lock_review_order()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_order_id uuid;
BEGIN
    FOR v_order_id IN
      SELECT DISTINCT order_id FROM (
          SELECT CASE WHEN TG_OP <> 'INSERT' THEN OLD.order_id END AS order_id
          UNION ALL
          SELECT CASE WHEN TG_OP <> 'DELETE' THEN NEW.order_id END
      ) x WHERE order_id IS NOT NULL ORDER BY order_id
    LOOP
        PERFORM 1 FROM rigun_food."order" o
        WHERE o.order_id = v_order_id FOR UPDATE;
    END LOOP;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS a_lock_review_order_trigger ON rigun_food.review;
CREATE TRIGGER a_lock_review_order_trigger
BEFORE INSERT OR UPDATE ON rigun_food.review
FOR EACH ROW EXECUTE FUNCTION rigun_food.a_lock_review_order();

-- E03/E10: check the final transaction state, not the temporary state
-- during INSERT order -> INSERT payment. Constraints are deferred to COMMIT.
-- Per BR-8.1, every persisted order must have exactly one successful payment
-- (the existing partial UNIQUE index enforces 'at most one').
CREATE OR REPLACE FUNCTION rigun_food.check_order_paid_at_commit()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_id uuid; v_status rigun_food.order_payment_status; v_success integer;
BEGIN
    IF TG_TABLE_NAME = 'payment' THEN
        IF TG_OP = 'DELETE' THEN v_id := OLD.order_id;
        ELSE v_id := NEW.order_id; END IF;
    ELSE
        IF TG_OP = 'DELETE' THEN RETURN NULL; END IF;
        v_id := NEW.order_id;
    END IF;

    -- An order can have been deleted later in the same transaction.
    SELECT pay_status INTO v_status
    FROM rigun_food."order" WHERE order_id = v_id;
    IF NOT FOUND THEN RETURN NULL; END IF;

    SELECT count(*)::integer INTO v_success
    FROM rigun_food.payment p
    WHERE p.order_id = v_id AND p.status = 'успех';

    IF v_success <> 1 THEN
        RAISE EXCEPTION 'Заказ % должен иметь ровно одну успешную оплату (найдено %)',
            v_id, v_success;
    END IF;
    IF v_status <> 'оплачен' THEN
        RAISE EXCEPTION 'Заказ % имеет успешную оплату, но pay_status = %',
            v_id, v_status;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS order_payment_required ON rigun_food."order";
CREATE CONSTRAINT TRIGGER order_payment_required
AFTER INSERT OR UPDATE ON rigun_food."order"
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION rigun_food.check_order_paid_at_commit();

DROP TRIGGER IF EXISTS payment_success_required ON rigun_food.payment;
CREATE CONSTRAINT TRIGGER payment_success_required
AFTER INSERT OR UPDATE OR DELETE ON rigun_food.payment
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION rigun_food.check_order_paid_at_commit();

-- On transfer, check the former order as well as the new one.
CREATE OR REPLACE FUNCTION rigun_food.check_old_payment_order_at_commit()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status rigun_food.order_payment_status; v_success integer;
BEGIN
    IF NEW.order_id IS NOT DISTINCT FROM OLD.order_id THEN RETURN NULL; END IF;
    SELECT pay_status INTO v_status FROM rigun_food."order"
    WHERE order_id = OLD.order_id;
    IF NOT FOUND THEN RETURN NULL; END IF;
    SELECT count(*)::integer INTO v_success FROM rigun_food.payment
    WHERE order_id = OLD.order_id AND status = 'успех';
    IF v_success <> 1 OR v_status <> 'оплачен' THEN
       RAISE EXCEPTION 'Перемещение платежа оставило заказ % без успешной оплаты', OLD.order_id;
    END IF;
    RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS payment_old_order_required ON rigun_food.payment;
CREATE CONSTRAINT TRIGGER payment_old_order_required
AFTER UPDATE OF order_id ON rigun_food.payment
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION rigun_food.check_old_payment_order_at_commit();

-- E14: rating is a derived AVG. On new rows it must be NULL until reviews exist.
-- Guard UPDATE for both products and restaurants; rating_change performs the valid updates.
CREATE OR REPLACE FUNCTION rigun_food.guard_aggregate_rating()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_expected numeric; v_id uuid; v_type rigun_food.review_entity_type;
BEGIN
    IF TG_TABLE_NAME = 'product' THEN
        v_id := NEW.product_id; v_type := 'блюдо';
    ELSE
        v_id := NEW.restaurant_id; v_type := 'ресторан';
    END IF;
    IF TG_OP = 'INSERT' THEN
        IF NEW.rating IS NOT NULL THEN
            RAISE EXCEPTION 'Начальный рейтинг должен быть NULL, пока нет отзывов';
        END IF;
        RETURN NEW;
    END IF;
    SELECT round(avg(r.rating), 2) INTO v_expected
    FROM rigun_food.review r WHERE r.entity_type=v_type AND r.entity_id=v_id;
    IF NEW.rating IS DISTINCT FROM v_expected THEN
        RAISE EXCEPTION 'Рейтинг должен соответствовать среднему по отзывам: %', v_expected;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS guard_aggregate_product_rating ON rigun_food.product;
CREATE TRIGGER guard_aggregate_product_rating
BEFORE INSERT OR UPDATE OF rating ON rigun_food.product
FOR EACH ROW EXECUTE FUNCTION rigun_food.guard_aggregate_rating();
DROP TRIGGER IF EXISTS guard_aggregate_restaurant_rating ON rigun_food.restaurant;
CREATE TRIGGER guard_aggregate_restaurant_rating
BEFORE INSERT OR UPDATE OF rating ON rigun_food.restaurant
FOR EACH ROW EXECUTE FUNCTION rigun_food.guard_aggregate_rating();

-- If a review was added later, ratings must match AVG; verify existing data.
DO $$
BEGIN
 IF EXISTS (SELECT 1 FROM rigun_food.product p WHERE p.rating IS DISTINCT FROM
       (SELECT round(avg(r.rating),2) FROM rigun_food.review r
        WHERE r.entity_type='блюдо' AND r.entity_id=p.product_id)) THEN
    RAISE EXCEPTION 'Существующие рейтинги блюд не согласованы';
 END IF;
 IF EXISTS (SELECT 1 FROM rigun_food.restaurant t WHERE t.rating IS DISTINCT FROM
       (SELECT round(avg(r.rating),2) FROM rigun_food.review r
        WHERE r.entity_type='ресторан' AND r.entity_id=t.restaurant_id)) THEN
    RAISE EXCEPTION 'Существующие рейтинги ресторанов не согласованы';
 END IF;
END;
$$;
