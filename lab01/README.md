# Практическая работа №1 — Развёртывание PostgreSQL и загрузка Olist

## Студент

- **ФИО:** `<заполнить>`
- **Группа:** `<заполнить>`
- **Вариант:** не предусмотрен

## Цель работы

Подготовить единый рабочий стенд PostgreSQL, загрузить открытый набор данных Brazilian E-Commerce Public Dataset by Olist и проверить базовую целостность отношений.

## Среда выполнения

- **СУБД:** PostgreSQL 17.11
- **Способ развёртывания:** Docker Compose
- **Docker-образ:** `postgres:17`
- **База данных:** `olist`
- **Пользователь:** `student`
- **Способ импорта:** `psql` с использованием `\\copy`
- **Клиентская среда:** PowerShell + Docker CLI

Фактическая версия PostgreSQL подтверждена результатом `check.sql`:

```text
PostgreSQL 17.11 (Debian 17.11-1.pgdg13+2)
```

## Структура проекта

```text
mosud-course/
├── README.md
├── .gitignore
└── lab01/
    ├── docker-compose.yml
    ├── schema.sql
    ├── check.sql
    └── README.md
```

Исходные CSV-файлы Olist хранятся локально в каталоге `data/olist` и в Git-репозиторий не включаются.

## Развёртывание PostgreSQL

Контейнер запущен через Docker Compose:

```powershell
cd .\lab01
docker compose up -d
```

Параметры подключения:

```text
Host: localhost
Port: 5432
Database: olist
User: student
Password: student
```

## Загрузка данных

CSV-файлы размещены в локальном каталоге:

```text
data/olist/
```

Загрузка схемы, данных, первичных и внешних ключей выполнялась через `psql`, запущенный внутри Docker-контейнера:

```powershell
Get-Content .\lab01\schema.sql | docker exec -i mosud-postgres psql -U student -d olist
```

В `schema.sql` используются команды `\\copy`, после которых добавляются ограничения целостности и выполняется `ANALYZE`.

## Фактический результат загрузки

Результат контрольного запроса `check.sql`:

| Таблица | Количество строк |
|---|---:|
| `customers` | 99 441 |
| `geolocation` | 1 000 163 |
| `order_items` | 112 650 |
| `order_payments` | 103 886 |
| `order_reviews` | 99 224 |
| `orders` | 99 441 |
| `product_category_name_translation` | 71 |
| `products` | 32 951 |
| `sellers` | 3 095 |

Фактические значения совпали с контрольными ориентирами, приведёнными в методичке.

## Проверка NULL в ключевых полях

По всем проверенным ключевым полям количество `NULL` составило:

```text
0
```

Проверялись:

- `customers.customer_id`
- `orders.order_id`
- `orders.customer_id`
- `order_items.order_id`
- `order_items.product_id`
- `order_items.seller_id`
- `order_payments.order_id`
- `order_reviews.review_id`
- `order_reviews.order_id`
- `products.product_id`
- `sellers.seller_id`
- `product_category_name_translation.product_category_name`

## Проверка ссылочной целостности

Количество осиротевших ссылок во всех проверенных отношениях:

```text
0
```

Проверены связи:

```text
orders -> customers
order_items -> orders
order_items -> products
order_items -> sellers
order_payments -> orders
order_reviews -> orders
```

## Проверка дубликатов составных ключей

Дубликаты не обнаружены:

```text
order_items (order_id, order_item_id)          — 0
order_payments (order_id, payment_sequential)  — 0
order_reviews (review_id, order_id)            — 0
```

## Статистика PostgreSQL

После загрузки данных выполнен `ANALYZE` для всех 9 таблиц.

Результат:

```text
ANALYZE
ANALYZE
ANALYZE
ANALYZE
ANALYZE
ANALYZE
ANALYZE
ANALYZE
ANALYZE
```

## Итог

В рамках практической работы:

1. PostgreSQL 17 развёрнут в Docker;
2. создана база данных `olist`;
3. созданы схемы `olist` и `lab`;
4. созданы 9 таблиц исходного набора Olist;
5. загружены все 9 CSV-файлов;
6. добавлены первичные и внешние ключи;
7. выполнена проверка количества строк;
8. проверены `NULL` в ключевых полях;
9. проверена ссылочная целостность;
10. проверены дубликаты составных ключей;
11. выполнен `ANALYZE`.

Все контрольные проверки завершились без выявленных нарушений.
