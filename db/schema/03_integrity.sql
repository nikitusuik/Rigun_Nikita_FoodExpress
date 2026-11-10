-- FOOD-101. Проверки связей между таблицами

-- Запрещаем добавлять блюдо из другого ресторана.
CREATE OR REPLACE FUNCTION rigun_food.check_order_product()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_restaurant uuid;
    v_product_restaurant uuid;
BEGIN
    SELECT restaurant_id
    INTO v_order_restaurant
    FROM rigun_food."order"
    WHERE order_id = NEW.order_id;

    SELECT restaurant_id
    INTO v_product_restaurant
    FROM rigun_food.product
    WHERE product_id = NEW.product_id;

    IF v_order_restaurant IS DISTINCT FROM v_product_restaurant THEN
        RAISE EXCEPTION
            'Блюдо не принадлежит ресторану заказа';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER check_order_product_trigger
BEFORE INSERT OR UPDATE
ON rigun_food.order_structure
FOR EACH ROW
EXECUTE FUNCTION rigun_food.check_order_product();


-- Проверяем сумму каждой попытки оплаты.
CREATE OR REPLACE FUNCTION rigun_food.check_payment_amount()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_amount numeric(14,2);
BEGIN
    SELECT total_amount
    INTO v_total_amount
    FROM rigun_food."order"
    WHERE order_id = NEW.order_id;

    IF NEW.amount IS DISTINCT FROM v_total_amount THEN
        RAISE EXCEPTION
            'Сумма платежа не совпадает с суммой заказа';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER check_payment_amount_trigger
BEFORE INSERT OR UPDATE
ON rigun_food.payment
FOR EACH ROW
EXECUTE FUNCTION rigun_food.check_payment_amount();
