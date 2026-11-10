-- FOOD-103. Удаление тестовых данных

CREATE OR REPLACE PROCEDURE rigun_food.erase_test_data()
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE
        rigun_food.review,
        rigun_food.payment,
        rigun_food.order_structure,
        rigun_food.courier_pay,
        rigun_food."order",
        rigun_food.product,
        rigun_food.product_category,
        rigun_food.restaurant,
        rigun_food.client_address,
        rigun_food.client,
        rigun_food.courier,
        rigun_food.address;
END;
$$;
