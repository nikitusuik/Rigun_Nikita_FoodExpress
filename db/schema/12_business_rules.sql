-- FOOD-101. Дополнительные бизнес-ограничения

-- BR-9.2. Отзыв разрешён только на объекты
-- собственного заказа клиента.

CREATE OR REPLACE FUNCTION rigun_food.check_review()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_order record;
BEGIN
    SELECT client_id, restaurant_id
    INTO v_order
    FROM rigun_food."order"
    WHERE order_id = NEW.order_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Заказ для отзыва не найден';
    END IF;

    IF NEW.client_id <> v_order.client_id THEN
        RAISE EXCEPTION
            'Клиент не может оставить отзыв на чужой заказ';
    END IF;

    IF NEW.entity_type = 'заказ' THEN
        IF NEW.entity_id <> NEW.order_id THEN
            RAISE EXCEPTION
                'Отзыв относится к другому заказу';
        END IF;

    ELSIF NEW.entity_type = 'ресторан' THEN
        IF NEW.entity_id <> v_order.restaurant_id THEN
            RAISE EXCEPTION
                'Ресторан не принадлежит заказу';
        END IF;

    ELSIF NEW.entity_type = 'блюдо' THEN
        IF NOT EXISTS (
            SELECT 1
            FROM rigun_food.order_structure os
            WHERE os.order_id = NEW.order_id
              AND os.product_id = NEW.entity_id
        ) THEN
            RAISE EXCEPTION
                'Блюдо отсутствует в заказе';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER check_review_trigger
BEFORE INSERT OR UPDATE
ON rigun_food.review
FOR EACH ROW
EXECUTE FUNCTION rigun_food.check_review();


-- BR-8.7. Обновляем агрегированный статус
-- оплаты заказа по фактическим попыткам.

CREATE OR REPLACE FUNCTION rigun_food.sync_payment_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_id uuid;
    v_new_status rigun_food.order_payment_status;
BEGIN
    -- Обрабатываем старый и новый заказ,
    -- в том числе перенос платежа между заказами.
    FOR v_order_id IN
        SELECT DISTINCT order_id
        FROM (
            SELECT CASE
                WHEN TG_OP <> 'INSERT'
                THEN OLD.order_id
            END AS order_id

            UNION ALL

            SELECT CASE
                WHEN TG_OP <> 'DELETE'
                THEN NEW.order_id
            END
        ) s
        WHERE order_id IS NOT NULL
    LOOP
        SELECT
            CASE
                WHEN count(*) FILTER (
                    WHERE status = 'успех'
                ) > 0
                    THEN 'оплачен'

                WHEN count(*) FILTER (
                    WHERE status = 'в_обработке'
                ) > 0
                    THEN 'ожидает'

                WHEN count(*) > 0
                    THEN 'ошибка'

                ELSE 'ожидает'
            END::rigun_food.order_payment_status
        INTO v_new_status
        FROM rigun_food.payment
        WHERE order_id = v_order_id;

        UPDATE rigun_food."order"
        SET pay_status = v_new_status
        WHERE order_id = v_order_id;
    END LOOP;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER sync_payment_status_trigger
AFTER INSERT OR UPDATE OR DELETE
ON rigun_food.payment
FOR EACH ROW
EXECUTE FUNCTION rigun_food.sync_payment_status();
