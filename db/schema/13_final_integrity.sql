-- FOOD-101. Дополнительная защита целостности

-- Нельзя перенести блюдо в другой ресторан,
-- если оно уже участвует в заказах другого ресторана.
CREATE OR REPLACE FUNCTION rigun_food.guard_product_restaurant()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.restaurant_id IS DISTINCT FROM OLD.restaurant_id
       AND EXISTS (
           SELECT 1
           FROM rigun_food.order_structure os
           JOIN rigun_food."order" o
             ON o.order_id = os.order_id
           WHERE os.product_id = OLD.product_id
             AND o.restaurant_id <> NEW.restaurant_id
       )
    THEN
        RAISE EXCEPTION
            'Нельзя перенести блюдо: оно участвует в заказах';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER guard_product_restaurant_trigger
BEFORE UPDATE OF restaurant_id ON rigun_food.product
FOR EACH ROW
EXECUTE FUNCTION rigun_food.guard_product_restaurant();


-- Защищаем существующие позиции и отзывы,
-- если меняется ресторан или клиент заказа.
CREATE OR REPLACE FUNCTION rigun_food.guard_order_links()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.restaurant_id IS DISTINCT FROM OLD.restaurant_id THEN
        IF EXISTS (
            SELECT 1
            FROM rigun_food.order_structure os
            JOIN rigun_food.product p
              ON p.product_id = os.product_id
            WHERE os.order_id = NEW.order_id
              AND p.restaurant_id <> NEW.restaurant_id
        ) THEN
            RAISE EXCEPTION
                'Нельзя изменить ресторан заказа с чужими блюдами';
        END IF;

        IF EXISTS (
            SELECT 1
            FROM rigun_food.review r
            WHERE r.order_id = NEW.order_id
              AND r.entity_type = 'ресторан'
              AND r.entity_id <> NEW.restaurant_id
        ) THEN
            RAISE EXCEPTION
                'Ресторан заказа противоречит существующим отзывам';
        END IF;
    END IF;

    IF NEW.client_id IS DISTINCT FROM OLD.client_id
       AND EXISTS (
           SELECT 1
           FROM rigun_food.review r
           WHERE r.order_id = NEW.order_id
             AND r.client_id <> NEW.client_id
       )
    THEN
        RAISE EXCEPTION
            'Нельзя изменить клиента заказа с чужими отзывами';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER guard_order_links_trigger
BEFORE UPDATE OF restaurant_id, client_id
ON rigun_food."order"
FOR EACH ROW
EXECUTE FUNCTION rigun_food.guard_order_links();


-- Проверка наличия хотя бы одной позиции в заказе.
-- Отложенная проверка разрешает сначала создать заказ,
-- а затем добавить позиции в той же транзакции.
CREATE OR REPLACE FUNCTION rigun_food.check_order_not_empty()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_order_id uuid;
BEGIN
    IF TG_TABLE_NAME = 'order' THEN
        v_order_id := NEW.order_id;
    ELSE
        v_order_id := OLD.order_id;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM rigun_food."order"
        WHERE order_id = v_order_id
    ) AND NOT EXISTS (
        SELECT 1
        FROM rigun_food.order_structure
        WHERE order_id = v_order_id
    ) THEN
        RAISE EXCEPTION
            'Заказ % не может быть без позиций', v_order_id;
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER order_requires_items
AFTER INSERT OR UPDATE ON rigun_food."order"
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION rigun_food.check_order_not_empty();

CREATE CONSTRAINT TRIGGER order_items_cannot_be_empty
AFTER DELETE OR UPDATE ON rigun_food.order_structure
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION rigun_food.check_order_not_empty();
