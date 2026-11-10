-- E03, E10, E14: TRUNCATE bypasses row-level and deferred constraint triggers.
-- Statement-level BEFORE TRUNCATE triggers protect consistent related data.
-- Normal erase_test_data() uses DELETE in FK order and remains supported.
-- Apply after 15_final_audit_fixes.sql, inside one transaction.

CREATE OR REPLACE FUNCTION rigun_food.guard_payment_truncate()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM rigun_food."order") THEN
        RAISE EXCEPTION USING
          ERRCODE = '23514',
          MESSAGE = 'Нельзя TRUNCATE payment при существующих заказах: BR-8.1 / BR-8.7',
          HINT = 'Для штатной очистки используйте CALL rigun_food.erase_test_data()';
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS guard_payment_truncate_trigger ON rigun_food.payment;
CREATE TRIGGER guard_payment_truncate_trigger
BEFORE TRUNCATE ON rigun_food.payment
FOR EACH STATEMENT EXECUTE FUNCTION rigun_food.guard_payment_truncate();

CREATE OR REPLACE FUNCTION rigun_food.guard_review_truncate()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM rigun_food.review)
       OR EXISTS (SELECT 1 FROM rigun_food.product WHERE rating IS NOT NULL)
       OR EXISTS (SELECT 1 FROM rigun_food.restaurant WHERE rating IS NOT NULL)
    THEN
        RAISE EXCEPTION USING
          ERRCODE = '23514',
          MESSAGE = 'Нельзя TRUNCATE review при существующих отзывах или рейтингах: BR-9.6',
          HINT = 'Для штатной очистки используйте CALL rigun_food.erase_test_data()';
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS guard_review_truncate_trigger ON rigun_food.review;
CREATE TRIGGER guard_review_truncate_trigger
BEFORE TRUNCATE ON rigun_food.review
FOR EACH STATEMENT EXECUTE FUNCTION rigun_food.guard_review_truncate();
