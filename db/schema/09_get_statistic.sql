-- FOOD-106. Статистика ресторанов

CREATE OR REPLACE FUNCTION rigun_food.get_statistic()
RETURNS TABLE (
    restaurant_name varchar,
    best_product_name varchar,
    total_amount numeric,
    avg_amount numeric,
    best_user varchar
)
LANGUAGE sql
STABLE
AS $$
WITH delivered AS (
    SELECT
        order_id,
        restaurant_id,
        client_id,
        total_amount
    FROM rigun_food."order"
    WHERE status = 'доставлен'
),
amounts AS (
    SELECT
        restaurant_id,
        sum(total_amount) AS total_amount,
        avg(total_amount) AS avg_amount
    FROM delivered
    GROUP BY restaurant_id
),
product_counts AS (
    SELECT
        d.restaurant_id,
        os.product_id,
        sum(os.quantity) AS qty
    FROM delivered d
    JOIN rigun_food.order_structure os
      ON os.order_id = d.order_id
    GROUP BY d.restaurant_id, os.product_id
),
best_products AS (
    SELECT DISTINCT ON (restaurant_id)
        restaurant_id,
        product_id
    FROM product_counts
    ORDER BY restaurant_id, qty DESC, random()
),
client_counts AS (
    SELECT
        restaurant_id,
        client_id,
        count(*) AS orders_count
    FROM delivered
    GROUP BY restaurant_id, client_id
),
best_clients AS (
    SELECT DISTINCT ON (restaurant_id)
        restaurant_id,
        client_id
    FROM client_counts
    ORDER BY restaurant_id, orders_count DESC, random()
)
SELECT
    r.restaurant_name,
    p.product_name,
    a.total_amount,
    a.avg_amount,
    c.login
FROM rigun_food.restaurant r
LEFT JOIN amounts a
    ON a.restaurant_id = r.restaurant_id
LEFT JOIN best_products bp
    ON bp.restaurant_id = r.restaurant_id
LEFT JOIN rigun_food.product p
    ON p.product_id = bp.product_id
LEFT JOIN best_clients bc
    ON bc.restaurant_id = r.restaurant_id
LEFT JOIN rigun_food.client c
    ON c.client_id = bc.client_id;
$$;
