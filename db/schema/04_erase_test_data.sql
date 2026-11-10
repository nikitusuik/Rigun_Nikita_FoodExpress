-- FOOD-103. Safe cleanup, including pending deferred events.
CREATE OR REPLACE PROCEDURE rigun_food.erase_test_data()
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM rigun_food.review;
    DELETE FROM rigun_food.payment;
    DELETE FROM rigun_food.order_structure;
    DELETE FROM rigun_food.courier_pay;
    DELETE FROM rigun_food."order";
    DELETE FROM rigun_food.product;
    DELETE FROM rigun_food.product_category;
    DELETE FROM rigun_food.restaurant;
    DELETE FROM rigun_food.client_address;
    DELETE FROM rigun_food.client;
    DELETE FROM rigun_food.courier;
    DELETE FROM rigun_food.address;
END;
$$;
