-- FOOD-102. Генератор тестовых данных

CREATE OR REPLACE PROCEDURE rigun_food.insert_test_data(value integer)
LANGUAGE plpgsql
AS $$
DECLARE
    i integer;
    j integer;
    k integer;
    v_id uuid;
    v_address uuid;
    v_order uuid;
    v_rest integer;
    v_client integer;
    v_price numeric(12,2);
    v_commission numeric(14,2);
    v_time timestamp;
    v_month_start timestamp;
    v_month_end timestamp;
    v_status rigun_food.order_status;
    v_entity_type rigun_food.review_entity_type;
    v_entity_id uuid;
    v_restaurants uuid[] := '{}';
    v_clients uuid[] := '{}';
    v_couriers uuid[] := '{}';
    v_categories uuid[] := '{}';
    v_products uuid[] := '{}';
    v_addresses uuid[] := '{}';
    v_courier_states rigun_food.courier_status[];
    v_product_states rigun_food.product_status[];
    v_order_states rigun_food.order_status[];
    v_payment_states rigun_food.payment_status[];
    v_pay_states rigun_food.order_payment_status[];
    v_review_types rigun_food.review_entity_type[];
    v_rest_states rigun_food.restaurant_status[];
    v_payment_types rigun_food.payment_type[];
    v_coefficient numeric(3,2);
    v_count bigint;
    v_sum numeric;
    v_month date;
    v_courier record;
BEGIN
    IF value IS NULL OR value < 1 THEN
        RAISE EXCEPTION 'value должен быть положительным числом';
    END IF;

    v_courier_states := enum_range(NULL::rigun_food.courier_status);
    v_product_states := enum_range(NULL::rigun_food.product_status);
    v_order_states := enum_range(NULL::rigun_food.order_status);
    v_payment_states := enum_range(NULL::rigun_food.payment_status);
    v_pay_states := enum_range(NULL::rigun_food.order_payment_status);
    v_review_types := enum_range(NULL::rigun_food.review_entity_type);
    v_rest_states := enum_range(NULL::rigun_food.restaurant_status);
    v_payment_types := enum_range(NULL::rigun_food.payment_type);

    -- Основные справочники и участники.
    FOR i IN 1..value LOOP
        v_id := exts.uuid_generate_v4();

        INSERT INTO rigun_food.client
            (client_id, login, password, phone_number)
        VALUES (
            v_id,
            'client_' || replace(v_id::text, '-', ''),
            md5(random()::text),
            '7' || lpad(
                ((('x' || substr(replace(v_id::text, '-', ''), 1, 12))
                    ::bit(48)::bigint % 100000000000))::text,
                11, '0')
        );

        v_clients := array_append(v_clients, v_id);

        v_id := exts.uuid_generate_v4();

        INSERT INTO rigun_food.courier
            (courier_id, fio, phone_number, status,
             hire_date, dismissal_date, coefficient)
        VALUES (
            v_id,
            'Курьер ' || i,
            '7' || lpad(
                ((('x' || substr(replace(v_id::text, '-', ''), 1, 12))
                    ::bit(48)::bigint % 100000000000))::text,
                11, '0'),
            v_courier_states[1 + (i % 3)],
            (date_trunc('month', CURRENT_DATE)
                - interval '5 months')::date,
            NULL,
            0.1
        );

        v_couriers := array_append(v_couriers, v_id);

        v_id := exts.uuid_generate_v4();

        INSERT INTO rigun_food.product_category
            (product_category_id, product_category_name)
        VALUES (
            v_id,
            'Категория ' || replace(v_id::text, '-', '')
        );

        v_categories := array_append(v_categories, v_id);

        v_address := exts.uuid_generate_v4();

        INSERT INTO rigun_food.address
            (address_id, street, house_number, apartment_office)
        VALUES (
            v_address, 'Ресторанная ' || i, i::text, NULL
        );

        v_id := exts.uuid_generate_v4();

        INSERT INTO rigun_food.restaurant
            (restaurant_id, restaurant_name, address_id,
             description, work_start, work_end,
             company_details, rating, status)
        VALUES (
            v_id,
            'Ресторан ' || left(v_id::text, 8),
            v_address,
            'Тестовый ресторан',
            time '09:00',
            time '22:00',
            'Тестовые реквизиты ' || v_id::text,
            NULL,
            v_rest_states[1]
        );

        v_restaurants := array_append(v_restaurants, v_id);
    END LOOP;

    -- Четыре адреса для каждого нового клиента.
    FOR i IN 1..value LOOP
        FOR j IN 1..4 LOOP
            v_address := exts.uuid_generate_v4();

            INSERT INTO rigun_food.address
                (address_id, street, house_number, apartment_office)
            VALUES (
                v_address,
                'Клиентская ' || i,
                j::text,
                i::text
            );

            INSERT INTO rigun_food.client_address
                (client_id, address_id)
            VALUES (v_clients[i], v_address);

            v_addresses := array_append(v_addresses, v_address);
        END LOOP;
    END LOOP;

    -- Пять блюд на каждый ресторан в сумме.
    FOR i IN 1..(value * 5) LOOP
        v_rest := ((i - 1) % value) + 1;
        v_id := exts.uuid_generate_v4();
        v_price := 1000 + ((i - 1) % 5) * 100;

        INSERT INTO rigun_food.product
            (product_id, product_name, product_category_id,
             price, restaurant_id, photo_url, rating,
             status, description)
        VALUES (
            v_id,
            'Блюдо ' || i,
            v_categories[v_rest],
            v_price,
            v_restaurants[v_rest],
            NULL,
            NULL,
            v_product_states[1],
            'Тестовое блюдо'
        );

        v_products := array_append(v_products, v_id);
    END LOOP;

    -- Заказы, состав, оплаты и отзывы.
    FOR i IN 1..(value * 5) LOOP
        v_rest := ((i - 1) % value) + 1;
        v_client := v_rest;
        j := ((i - 1) % 4) + 1;
        k := (v_client - 1) * 4 + j;

        v_month_start :=
            date_trunc('month', localtimestamp)
            - (((i - 1) % 6) * interval '1 month');

        v_month_end := LEAST(
            v_month_start + interval '20 days',
            localtimestamp - interval '2 hours'
        );

        v_time := v_month_start
            + random() * (v_month_end - v_month_start);

        v_price := 1000 + ((i - 1) % 5) * 100;
        v_commission := round(v_price * 0.10, 2);

        IF i <= value OR i % 5 <> 0 THEN
            v_status := v_order_states[4];
        ELSE
            v_status := v_order_states[5];
        END IF;

        v_order := exts.uuid_generate_v4();

        INSERT INTO rigun_food."order"
            (order_id, courier_id, client_id, address_id,
             restaurant_id, order_timestamp, delivery_timestamp,
             order_amount, commission, total_amount,
             status, pay_status, description)
        VALUES (
            v_order,
            v_couriers[v_rest],
            v_clients[v_client],
            v_addresses[k],
            v_restaurants[v_rest],
            v_time,
            CASE WHEN v_status = v_order_states[4]
                 THEN v_time + interval '1 hour'
                 ELSE NULL END,
            v_price,
            v_commission,
            v_price + v_commission,
            v_status,
            CASE WHEN v_status = v_order_states[4]
                 THEN v_pay_states[2]
                 ELSE v_pay_states[3] END,
            'Тестовый заказ'
        );

        INSERT INTO rigun_food.order_structure
            (order_id, product_id, quantity)
        VALUES (v_order, v_products[i], 1);

        INSERT INTO rigun_food.payment
            (payment_id, order_id, payment_type, amount,
             transaction_id, transaction_timestamp, status)
        VALUES (
            exts.uuid_generate_v4(),
            v_order,
            v_payment_types[1 + ((i - 1) % 3)],
            v_price + v_commission,
            exts.uuid_generate_v4()::text,
            v_time,
            CASE WHEN v_status = v_order_states[4]
                 THEN v_payment_states[1]
                 ELSE v_payment_states[2] END
        );

        v_entity_type := v_review_types[1 + ((i - 1) % 3)];

        CASE v_entity_type
            WHEN 'блюдо' THEN v_entity_id := v_products[i];
            WHEN 'ресторан' THEN v_entity_id := v_restaurants[v_rest];
            ELSE v_entity_id := v_order;
        END CASE;

        INSERT INTO rigun_food.review
            (review_id, client_id, review_timestamp,
             entity_id, entity_type, order_id,
             description, photo_url, rating)
        VALUES (
            exts.uuid_generate_v4(),
            v_clients[v_client],
            v_time + interval '1 hour',
            v_entity_id,
            v_entity_type,
            v_order,
            'Тестовый отзыв',
            NULL,
            1 + ((i - 1) % 5)
        );
    END LOOP;

    -- История выплат за шесть календарных месяцев.
    -- Пересчитываем и старых курьеров, поскольку процедура
    -- допускает повторные вызовы.
    FOR v_courier IN
        SELECT courier_id, status
        FROM rigun_food.courier
    LOOP
        v_coefficient := 0.1;

        FOR j IN REVERSE 5..0 LOOP
            v_month := (
                date_trunc('month', CURRENT_DATE)
                - j * interval '1 month'
            )::date;

            SELECT count(*), COALESCE(sum(commission), 0)
            INTO v_count, v_sum
            FROM rigun_food."order"
            WHERE courier_id = v_courier.courier_id
              AND status = v_order_states[4]
              AND order_timestamp >= v_month
              AND order_timestamp < v_month + interval '1 month';

            INSERT INTO rigun_food.courier_pay
                (year, month, courier_id, amount, coefficient_used)
            VALUES (
                extract(year FROM v_month)::integer,
                extract(month FROM v_month)::integer,
                v_courier.courier_id,
                round(v_sum * v_coefficient, 2),
                v_coefficient
            )
            ON CONFLICT (year, month, courier_id)
            DO UPDATE SET
                amount = EXCLUDED.amount,
                coefficient_used = EXCLUDED.coefficient_used;

            v_coefficient := CASE
                WHEN v_count <= 150 THEN 0.1
                WHEN v_count <= 250 THEN 0.2
                WHEN v_count <= 500 THEN 0.3
                ELSE 0.5
            END;
        END LOOP;

        IF v_courier.status <> v_courier_states[4] THEN
            UPDATE rigun_food.courier
            SET coefficient = v_coefficient
            WHERE courier_id = v_courier.courier_id;
        END IF;
    END LOOP;
END;
$$;
