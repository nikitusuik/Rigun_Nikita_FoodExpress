# FoodExpress — база данных

Добро пожаловать в проект. Твоя задача — спроектировать и реализовать базу данных для сервиса доставки еды.

## С чего начать
1. Прочитай [онбординг](docs/onboarding.md) — это твой первый рабочий день.
2. Изучи [бизнес-правила](docs/company-rules.md).
3. Открой [бэклог](docs/backlog.md) — там твои задачи.

## Если ты никогда не работал с Git
1. Посмотри [скринкаст](docs/git-screencast.md) (10 минут).
2. Держи под рукой [шпаргалку](docs/git-cheatsheet.md).

## Сдача работы
Все требования к составу файлов, формату резервной копии и процессу сдачи описаны в файле [docs/acceptance.md](docs/acceptance.md).

## Платформы
Репозиторий зеркалируется на две платформы. Форкай ту, где тебе удобнее:
- GitHub: [`<ссылка_на_github>`](https://github.com/NKhashchanov/total_designing_db_2026)
- GitVerse: [`<ссылка_на_gitverse>`](https://gitverse.ru/nkhashchanov/total_designing_db_2026)
## Реализация FoodExpress — Никита Ригун

СУБД: PostgreSQL 15.
Рабочая схема: `rigun_food`.

SQL-скрипты находятся в `db/schema/`.

Резервная копия: `db/foodexpress_rigun.backup`.

Документация:
- `db/constraints.md` — ограничения базы данных.
- `db/tests.md` — результаты тестирования.

Для восстановления архива необходимо заранее обеспечить
доступность `exts.uuid_generate_v4()` (расширение uuid-ossp
в схеме exts).

Для проверки используются процедуры `insert_test_data`,
`erase_test_data`, `add_product`, `courier_salary`,
функция `get_statistic` и представление `how_much_money`.
