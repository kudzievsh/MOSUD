\pset pager off
\echo '============================================================'
\echo 'LAB 04. Variant 3. Category revenue and complex JOINs'
\echo '============================================================'

SET search_path TO olist, public;

/*
Практическая работа № 4, вариант 3.
Сценарий: «Выручка категорий».
Минимальный маршрут: orders -> order_items -> products -> product_category_name_translation.

Предполагаемые кратности связей:
1) orders -> order_items:
   1:N. Один заказ может содержать несколько позиций; каждая позиция относится к одному заказу.

2) order_items -> products:
   N:1. Многие позиции заказов могут ссылаться на один и тот же товар.
   Если смотреть orders <-> products через order_items, связь в целом M:N.

3) products -> product_category_name_translation:
   N:0..1 на уровне строк products: много товаров могут иметь одну категорию,
   а для категории может существовать не более одной строки перевода.
   LEFT JOIN используется специально, чтобы товары/категории без перевода не исчезали.

Композиция реляционной алгебры для основного запроса (с агрегацией):
γ_{category; COUNT_DISTINCT(order_id)->orders_count,
              COUNT(*)->items_count,
              SUM(price)->revenue}
(
  (orders ⋈_{orders.order_id = order_items.order_id} order_items)
  ⋈_{order_items.product_id = products.product_id} products
  ⟕_{products.product_category_name = translation.product_category_name} translation
)

Примечание: выручкой здесь считается сумма order_items.price.
*/

\echo ''
\echo '1. Main query: category revenue (4 tables, translation via LEFT JOIN)'

DROP VIEW IF EXISTS pg_temp.lab04_category_revenue;
CREATE TEMP VIEW lab04_category_revenue AS
SELECT
    COALESCE(
        t.product_category_name_english,
        p.product_category_name,
        '[NULL category]'
    ) AS category,
    COUNT(DISTINCT o.order_id) AS orders_count,
    COUNT(*) AS items_count,
    ROUND(SUM(oi.price)::numeric, 2) AS revenue
FROM olist.orders AS o
JOIN olist.order_items AS oi
    ON oi.order_id = o.order_id
JOIN olist.products AS p
    ON p.product_id = oi.product_id
LEFT JOIN olist.product_category_name_translation AS t
    ON t.product_category_name = p.product_category_name
GROUP BY
    COALESCE(
        t.product_category_name_english,
        p.product_category_name,
        '[NULL category]'
    );

SELECT *
FROM lab04_category_revenue
ORDER BY revenue DESC, category
LIMIT 20;

\echo ''
\echo '2. LEFT JOIN diagnostic: categories are preserved even without translation'

SELECT
    COUNT(DISTINCT p.product_category_name) FILTER (
        WHERE p.product_category_name IS NOT NULL
    ) AS source_categories,
    COUNT(DISTINCT p.product_category_name) FILTER (
        WHERE p.product_category_name IS NOT NULL
          AND t.product_category_name IS NOT NULL
    ) AS translated_categories,
    COUNT(DISTINCT p.product_category_name) FILTER (
        WHERE p.product_category_name IS NOT NULL
          AND t.product_category_name IS NULL
    ) AS untranslated_categories
FROM olist.products AS p
LEFT JOIN olist.product_category_name_translation AS t
    ON t.product_category_name = p.product_category_name;

\echo ''
\echo '3. Anti-join: categories that have no translation row'

SELECT
    p.product_category_name,
    COUNT(*) AS products_count
FROM olist.products AS p
LEFT JOIN olist.product_category_name_translation AS t
    ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL
GROUP BY p.product_category_name
ORDER BY p.product_category_name;

\echo ''
\echo 'Anti-join count'
SELECT COUNT(*) AS untranslated_category_count
FROM (
    SELECT DISTINCT p.product_category_name
    FROM olist.products AS p
    LEFT JOIN olist.product_category_name_translation AS t
        ON t.product_category_name = p.product_category_name
    WHERE p.product_category_name IS NOT NULL
      AND t.product_category_name IS NULL
) AS x;

/*
Почему следующий JOIN ошибочный:
у одного order_id может быть несколько строк одновременно и в order_items,
и в order_payments. При прямом соединении обеих таблиц по order_id каждая
позиция заказа комбинируется с каждой строкой платежа этого же заказа.
Для заказа с I позициями и P платежами получается I * P строк.
Из-за этого SUM(oi.price) и SUM(op.payment_value) могут быть завышены.
*/

\echo ''
\echo '4. INTENTIONALLY WRONG JOIN: items x payments multiplication'

DROP VIEW IF EXISTS pg_temp.lab04_wrong_join;
CREATE TEMP VIEW lab04_wrong_join AS
SELECT
    o.order_id,
    oi.order_item_id,
    op.payment_sequential,
    oi.price,
    op.payment_value
FROM olist.orders AS o
JOIN olist.order_items AS oi
    ON oi.order_id = o.order_id
JOIN olist.order_payments AS op
    ON op.order_id = o.order_id;

SELECT
    COUNT(*) AS wrong_join_rows,
    ROUND(SUM(price)::numeric, 2) AS wrong_sum_item_price,
    ROUND(SUM(payment_value)::numeric, 2) AS wrong_sum_payment_value
FROM lab04_wrong_join;

\echo ''
\echo 'Reference totals on the same scope (orders that have both items and payments)'

SELECT
    (SELECT COUNT(*)
     FROM olist.order_items AS oi
     WHERE EXISTS (
         SELECT 1
         FROM olist.order_payments AS op
         WHERE op.order_id = oi.order_id
     )) AS item_rows_without_multiplication,
    (SELECT ROUND(SUM(oi.price)::numeric, 2)
     FROM olist.order_items AS oi
     WHERE EXISTS (
         SELECT 1
         FROM olist.order_payments AS op
         WHERE op.order_id = oi.order_id
     )) AS correct_sum_item_price,
    (SELECT ROUND(SUM(op.payment_value)::numeric, 2)
     FROM olist.order_payments AS op
     WHERE EXISTS (
         SELECT 1
         FROM olist.order_items AS oi
         WHERE oi.order_id = op.order_id
     )) AS correct_sum_payment_value;

/*
Исправление: сначала агрегируем каждую связь 1:N до одной строки на order_id,
а затем соединяем агрегаты. Теперь один заказ участвует в итоговом JOIN ровно
одной строкой, поэтому суммы не размножаются.
*/

\echo ''
\echo '5. CORRECTED JOIN: pre-aggregate items and payments to one row per order'

DROP VIEW IF EXISTS pg_temp.lab04_items_by_order;
CREATE TEMP VIEW lab04_items_by_order AS
SELECT
    order_id,
    COUNT(*) AS item_count,
    ROUND(SUM(price)::numeric, 2) AS item_total
FROM olist.order_items
GROUP BY order_id;

DROP VIEW IF EXISTS pg_temp.lab04_payments_by_order;
CREATE TEMP VIEW lab04_payments_by_order AS
SELECT
    order_id,
    COUNT(*) AS payment_count,
    ROUND(SUM(payment_value)::numeric, 2) AS payment_total
FROM olist.order_payments
GROUP BY order_id;

DROP VIEW IF EXISTS pg_temp.lab04_correct_join;
CREATE TEMP VIEW lab04_correct_join AS
SELECT
    o.order_id,
    i.item_count,
    i.item_total,
    p.payment_count,
    p.payment_total
FROM olist.orders AS o
JOIN lab04_items_by_order AS i
    ON i.order_id = o.order_id
JOIN lab04_payments_by_order AS p
    ON p.order_id = o.order_id;

SELECT
    COUNT(*) AS orders_after_preaggregation,
    ROUND(SUM(item_total)::numeric, 2) AS corrected_sum_item_price,
    ROUND(SUM(payment_total)::numeric, 2) AS corrected_sum_payment_value
FROM lab04_correct_join;

\echo ''
\echo '6. Proof that pre-aggregation matches the reference totals'

WITH reference AS (
    SELECT
        (SELECT SUM(oi.price)
         FROM olist.order_items AS oi
         WHERE EXISTS (
             SELECT 1
             FROM olist.order_payments AS op
             WHERE op.order_id = oi.order_id
         )) AS ref_item_total,
        (SELECT SUM(op.payment_value)
         FROM olist.order_payments AS op
         WHERE EXISTS (
             SELECT 1
             FROM olist.order_items AS oi
             WHERE oi.order_id = op.order_id
         )) AS ref_payment_total
), corrected AS (
    SELECT
        SUM(item_total) AS fixed_item_total,
        SUM(payment_total) AS fixed_payment_total
    FROM lab04_correct_join
)
SELECT
    ROUND((c.fixed_item_total - r.ref_item_total)::numeric, 2) AS item_total_difference,
    ROUND((c.fixed_payment_total - r.ref_payment_total)::numeric, 2) AS payment_total_difference,
    (c.fixed_item_total = r.ref_item_total) AS item_total_is_equal,
    (c.fixed_payment_total = r.ref_payment_total) AS payment_total_is_equal
FROM reference AS r
CROSS JOIN corrected AS c;

\echo ''
\echo '============================================================'
\echo 'FINAL RESULTS FOR CHECKING'
\echo '============================================================'

WITH left_join_stats AS (
    SELECT
        COUNT(DISTINCT p.product_category_name) FILTER (
            WHERE p.product_category_name IS NOT NULL
        ) AS source_categories,
        COUNT(DISTINCT p.product_category_name) FILTER (
            WHERE p.product_category_name IS NOT NULL
              AND t.product_category_name IS NULL
        ) AS untranslated_categories
    FROM olist.products AS p
    LEFT JOIN olist.product_category_name_translation AS t
        ON t.product_category_name = p.product_category_name
), wrong_stats AS (
    SELECT
        COUNT(*) AS wrong_join_rows,
        SUM(price) AS wrong_item_total,
        SUM(payment_value) AS wrong_payment_total
    FROM lab04_wrong_join
), correct_stats AS (
    SELECT
        COUNT(*) AS correct_order_rows,
        SUM(item_total) AS correct_item_total,
        SUM(payment_total) AS correct_payment_total
    FROM lab04_correct_join
)
SELECT
    (SELECT COUNT(*) FROM lab04_category_revenue) AS category_rows,
    l.source_categories,
    l.untranslated_categories,
    w.wrong_join_rows,
    c.correct_order_rows,
    ROUND((w.wrong_item_total - c.correct_item_total)::numeric, 2) AS item_overstatement_due_to_wrong_join,
    ROUND((w.wrong_payment_total - c.correct_payment_total)::numeric, 2) AS payment_overstatement_due_to_wrong_join
FROM left_join_stats AS l
CROSS JOIN wrong_stats AS w
CROSS JOIN correct_stats AS c;
