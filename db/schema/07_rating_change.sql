-- FOOD-105. Автоматический пересчёт рейтингов

CREATE OR REPLACE FUNCTION rigun_food.rating_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- При удалении или изменении отзыва пересчитываем
    -- рейтинг старого объекта.
    IF TG_OP IN ('UPDATE', 'DELETE') THEN

        IF OLD.entity_type = 'блюдо' THEN
            UPDATE rigun_food.product p
            SET rating = (
                SELECT round(avg(r.rating), 2)
                FROM rigun_food.review r
                WHERE r.entity_type = 'блюдо'
                  AND r.entity_id = OLD.entity_id
            )
            WHERE p.product_id = OLD.entity_id;

        ELSIF OLD.entity_type = 'ресторан' THEN
            UPDATE rigun_food.restaurant t
            SET rating = (
                SELECT round(avg(r.rating), 2)
                FROM rigun_food.review r
                WHERE r.entity_type = 'ресторан'
                  AND r.entity_id = OLD.entity_id
            )
            WHERE t.restaurant_id = OLD.entity_id;
        END IF;
    END IF;

    -- При добавлении или изменении отзыва пересчитываем
    -- рейтинг нового объекта.
    IF TG_OP IN ('INSERT', 'UPDATE') THEN

        IF NEW.entity_type = 'блюдо' THEN
            UPDATE rigun_food.product p
            SET rating = (
                SELECT round(avg(r.rating), 2)
                FROM rigun_food.review r
                WHERE r.entity_type = 'блюдо'
                  AND r.entity_id = NEW.entity_id
            )
            WHERE p.product_id = NEW.entity_id;

        ELSIF NEW.entity_type = 'ресторан' THEN
            UPDATE rigun_food.restaurant t
            SET rating = (
                SELECT round(avg(r.rating), 2)
                FROM rigun_food.review r
                WHERE r.entity_type = 'ресторан'
                  AND r.entity_id = NEW.entity_id
            )
            WHERE t.restaurant_id = NEW.entity_id;
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER rating_change_trigger
AFTER INSERT OR UPDATE OR DELETE
ON rigun_food.review
FOR EACH ROW
EXECUTE FUNCTION rigun_food.rating_change();
