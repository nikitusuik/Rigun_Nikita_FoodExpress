-- FOOD-109. Права пользователя inspector

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname = 'inspector'
    ) THEN
        CREATE ROLE inspector LOGIN PASSWORD 'NetoSQL2025';
    ELSE
        ALTER ROLE inspector LOGIN PASSWORD 'NetoSQL2025';
    END IF;
END;
$$;


GRANT ALL PRIVILEGES ON SCHEMA rigun_food TO inspector;
GRANT USAGE ON SCHEMA exts TO inspector;

GRANT ALL PRIVILEGES ON ALL TABLES
IN SCHEMA rigun_food TO inspector;

GRANT ALL PRIVILEGES ON ALL SEQUENCES
IN SCHEMA rigun_food TO inspector;

GRANT EXECUTE ON ALL FUNCTIONS
IN SCHEMA rigun_food TO inspector;

GRANT EXECUTE ON ALL PROCEDURES
IN SCHEMA rigun_food TO inspector;

ALTER DEFAULT PRIVILEGES
IN SCHEMA rigun_food
GRANT ALL ON TABLES TO inspector;

ALTER DEFAULT PRIVILEGES
IN SCHEMA rigun_food
GRANT EXECUTE ON FUNCTIONS TO inspector;
