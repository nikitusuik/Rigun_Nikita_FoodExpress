-- FOOD-108. Финансовый отчёт FoodExpress
-- Отчёт охватывает все месяцы с доставленными заказами,
-- включая месяцы без доставок между ними.

CREATE OR REPLACE VIEW rigun_food.how_much_money AS
WITH RECURSIVE

delivered_orders AS (
    SELECT
        date_trunc('month', order_timestamp)::date AS month_start,
        order_amount,
        total_amount
    FROM rigun_food."order"
    WHERE status = 'доставлен'
),

month_bounds AS (
    SELECT
        min(month_start) AS first_month,
        max(month_start) AS last_month
    FROM delivered_orders
),

months AS (
    SELECT first_month AS month_start
    FROM month_bounds
    WHERE first_month IS NOT NULL

    UNION ALL

    SELECT (m.month_start + interval '1 month')::date
    FROM months m
    CROSS JOIN month_bounds b
    WHERE m.month_start < b.last_month
),

monthly_orders AS (
    SELECT
        month_start,
        sum(order_amount) AS sum_no_commission,
        sum(total_amount) AS sum_with_commission
    FROM delivered_orders
    GROUP BY month_start
),

monthly_salary AS (
    SELECT
        make_date(year, month, 1) AS month_start,
        sum(amount) AS salary_amount
    FROM rigun_food.courier_pay
    GROUP BY year, month
),

monthly_totals AS (
    SELECT
        m.month_start,
        COALESCE(o.sum_no_commission, 0)::numeric
            AS sum_no_commission,
        COALESCE(o.sum_with_commission, 0)::numeric
            AS sum_with_commission,
        (
            COALESCE(o.sum_with_commission, 0)
            - COALESCE(o.sum_no_commission, 0)
        )::numeric AS commission,
        COALESCE(s.salary_amount, 0)::numeric AS courier_pay
    FROM months m
    LEFT JOIN monthly_orders o
        ON o.month_start = m.month_start
    LEFT JOIN monthly_salary s
        ON s.month_start = m.month_start
),

with_previous AS (
    SELECT
        *,
        lag(commission) OVER (ORDER BY month_start)
            AS prev_commission
    FROM monthly_totals
)

SELECT
    to_char(month_start, 'YYYY-MM')::text AS year_month,
    sum_no_commission,
    sum_with_commission,
    commission,
    prev_commission,
    (commission - prev_commission)::numeric AS commission_diff,
    courier_pay,
    (commission - courier_pay)::numeric AS net_profit
FROM with_previous;
