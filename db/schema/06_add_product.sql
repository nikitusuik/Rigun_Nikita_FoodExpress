-- FOOD-104. Добавление блюда

CREATE OR REPLACE PROCEDURE rigun_food.add_product(
    p_product_name varchar,
    p_product_category_id uuid,
    p_price numeric,
    p_restaurant_id uuid,
    p_photo_url text,
    p_rating numeric,
    p_status rigun_food.product_status,
    p_description text
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM rigun_food.restaurant
        WHERE restaurant_id = p_restaurant_id
    ) THEN
        RAISE EXCEPTION 'Ресторан с ID % не найден', p_restaurant_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM rigun_food.product_category
        WHERE product_category_id = p_product_category_id
    ) THEN
        RAISE EXCEPTION 'Категория с ID % не найдена',
            p_product_category_id;
    END IF;

    IF p_price IS NULL OR p_price < 0 THEN
        RAISE EXCEPTION 'Цена блюда должна быть неотрицательной';
    END IF;

    -- Rating is calculated exclusively from reviews (FOOD-105, BR-9.6).
    IF p_rating IS NOT NULL THEN
        RAISE EXCEPTION 'Рейтинг нового блюда должен быть NULL до появления отзывов';
    END IF;

    INSERT INTO rigun_food.product (
        product_id,
        product_name,
        product_category_id,
        price,
        restaurant_id,
        photo_url,
        rating,
        status,
        description
    )
    VALUES (
        exts.uuid_generate_v4(),
        p_product_name,
        p_product_category_id,
        p_price,
        p_restaurant_id,
        p_photo_url,
        p_rating,
        p_status,
        p_description
    );
END;
$$;
