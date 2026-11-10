-- Первоначальный пересчёт рейтингов

UPDATE rigun_food.product p
SET rating = (
    SELECT round(avg(r.rating), 2)
    FROM rigun_food.review r
    WHERE r.entity_type = 'блюдо'
      AND r.entity_id = p.product_id
);

UPDATE rigun_food.restaurant t
SET rating = (
    SELECT round(avg(r.rating), 2)
    FROM rigun_food.review r
    WHERE r.entity_type = 'ресторан'
      AND r.entity_id = t.restaurant_id
);
