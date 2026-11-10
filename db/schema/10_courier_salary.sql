-- FOOD-107. Расчёт зарплаты курьеров

CREATE OR REPLACE PROCEDURE rigun_food.courier_salary()
LANGUAGE plpgsql
AS $$
DECLARE
    v_month_start timestamp;
    v_month_end timestamp;
    v_year integer;
    v_month integer;
    v_courier record;
    v_count bigint;
    v_commission numeric;
    v_current_coefficient numeric(3,2);
    v_next_coefficient numeric(3,2);
BEGIN
    v_month_start := date_trunc('month', CURRENT_TIMESTAMP);
    v_month_end := v_month_start + interval '1 month';

    v_year := extract(year FROM v_month_start)::integer;
    v_month := extract(month FROM v_month_start)::integer;

    FOR v_courier IN
        SELECT courier_id, status, coefficient
        FROM rigun_food.courier
    LOOP
        SELECT
            count(*),
            COALESCE(sum(commission), 0)
        INTO v_count, v_commission
        FROM rigun_food."order"
        WHERE courier_id = v_courier.courier_id
          AND status = 'доставлен'
          AND order_timestamp >= v_month_start
          AND order_timestamp < v_month_end;

        -- Если зарплата уже рассчитана, используем
        -- коэффициент, зафиксированный за этот месяц.
        SELECT coefficient_used
        INTO v_current_coefficient
        FROM rigun_food.courier_pay
        WHERE year = v_year
          AND month = v_month
          AND courier_id = v_courier.courier_id;

        IF NOT FOUND THEN
            v_current_coefficient := v_courier.coefficient;
        END IF;

        v_next_coefficient := CASE
            WHEN v_count <= 150 THEN 0.1
            WHEN v_count <= 250 THEN 0.2
            WHEN v_count <= 500 THEN 0.3
            ELSE 0.5
        END;

        INSERT INTO rigun_food.courier_pay (
            year,
            month,
            courier_id,
            amount,
            coefficient_used
        )
        VALUES (
            v_year,
            v_month,
            v_courier.courier_id,
            round(v_commission * v_current_coefficient, 2),
            v_current_coefficient
        )
        ON CONFLICT (year, month, courier_id)
        DO UPDATE SET
            amount = EXCLUDED.amount,
            coefficient_used = EXCLUDED.coefficient_used;

        -- Уволенным новый коэффициент не назначаем.
        IF v_courier.status <> 'уволен' THEN
            UPDATE rigun_food.courier
            SET coefficient = v_next_coefficient
            WHERE courier_id = v_courier.courier_id;
        END IF;
    END LOOP;
END;
$$;
