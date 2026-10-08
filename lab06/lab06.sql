\pset pager off
\echo '============================================================'
\echo 'LAB 06. Variant 3.'
\echo '============================================================'

SET search_path TO olist, public;
SET max_parallel_workers_per_gather = 0;

-- ============================================================
-- 0. Source diagnostics
-- ============================================================
\echo ''
\echo '0. Source diagnostics'
SELECT
    COUNT(*) AS item_rows,
    COUNT(DISTINCT order_id) AS orders_with_items,
    ROUND(SUM(price)::numeric, 2) AS total_item_revenue
FROM olist.order_items;

-- ============================================================
-- 1. Main solution.
-- ============================================================
DROP VIEW IF EXISTS pg_temp.lab06_main;
CREATE TEMP VIEW lab06_main AS
SELECT
    o.order_id,
    (
        SELECT SUM(oi.price)
        FROM olist.order_items AS oi
        WHERE oi.order_id = o.order_id
    ) AS order_total
FROM olist.orders AS o
WHERE EXISTS (
    SELECT 1
    FROM olist.order_items AS oi_exists
    WHERE oi_exists.order_id = o.order_id
)
AND (
    SELECT SUM(oi.price)
    FROM olist.order_items AS oi
    WHERE oi.order_id = o.order_id
) > (
    SELECT AVG(t.order_total)
    FROM (
        SELECT oi2.order_id, SUM(oi2.price) AS order_total
        FROM olist.order_items AS oi2
        GROUP BY oi2.order_id
    ) AS t
);

\echo ''
\echo '1. Main solution: correlated/scalar subqueries + EXISTS'
SELECT COUNT(*) AS qualifying_orders
FROM pg_temp.lab06_main;

SELECT order_id, ROUND(order_total::numeric, 2) AS order_total
FROM pg_temp.lab06_main
ORDER BY order_total DESC, order_id
LIMIT 10;

-- ============================================================
-- 2. Alternative solution using CTE + pre-aggregation.
-- ============================================================
DROP VIEW IF EXISTS pg_temp.lab06_cte;
CREATE TEMP VIEW lab06_cte AS
WITH order_totals AS (
    SELECT
        oi.order_id,
        SUM(oi.price) AS order_total
    FROM olist.order_items AS oi
    GROUP BY oi.order_id
),
average_total AS (
    SELECT AVG(order_total) AS avg_order_total
    FROM order_totals
)
SELECT
    ot.order_id,
    ot.order_total
FROM order_totals AS ot
CROSS JOIN average_total AS a
WHERE ot.order_total > a.avg_order_total;

\echo ''
\echo '2. Alternative solution: CTE + pre-aggregation'
SELECT COUNT(*) AS qualifying_orders
FROM pg_temp.lab06_cte;

-- ============================================================
-- 3. EXCEPT equivalence check in both directions.
-- ============================================================
\echo ''
\echo '3. Equivalence check with EXCEPT in both directions'
SELECT
    'main EXCEPT cte' AS check_name,
    COUNT(*) AS mismatch_count
FROM (
    SELECT order_id, order_total FROM pg_temp.lab06_main
    EXCEPT
    SELECT order_id, order_total FROM pg_temp.lab06_cte
) AS d;

SELECT
    'cte EXCEPT main' AS check_name,
    COUNT(*) AS mismatch_count
FROM (
    SELECT order_id, order_total FROM pg_temp.lab06_cte
    EXCEPT
    SELECT order_id, order_total FROM pg_temp.lab06_main
) AS d;

-- ============================================================
-- 4. ANY / ALL demonstration.
-- ============================================================
\echo ''
\echo '4. ANY / ALL demonstration'
WITH order_totals AS (
    SELECT order_id, SUM(price) AS order_total
    FROM olist.order_items
    GROUP BY order_id
),
comparison_set AS (
    SELECT order_total
    FROM order_totals
    ORDER BY order_id
    LIMIT 5
)
SELECT
    (SELECT COUNT(*)
     FROM order_totals ot
     WHERE ot.order_total > ANY (SELECT order_total FROM comparison_set)) AS greater_than_any_count,
    (SELECT COUNT(*)
     FROM order_totals ot
     WHERE ot.order_total > ALL (SELECT order_total FROM comparison_set)) AS greater_than_all_count,
    (SELECT MIN(order_total) FROM comparison_set) AS comparison_min,
    (SELECT MAX(order_total) FROM comparison_set) AS comparison_max;

-- ============================================================
-- 5. Final summary for checking.
-- ============================================================
\echo ''
\echo '============================================================'
\echo 'FINAL RESULTS FOR CHECKING'
\echo '============================================================'
WITH order_totals AS (
    SELECT order_id, SUM(price) AS order_total
    FROM olist.order_items
    GROUP BY order_id
),
comparison_set AS (
    SELECT order_total
    FROM order_totals
    ORDER BY order_id
    LIMIT 5
),
main_minus_cte AS (
    SELECT order_id, order_total FROM pg_temp.lab06_main
    EXCEPT
    SELECT order_id, order_total FROM pg_temp.lab06_cte
),
cte_minus_main AS (
    SELECT order_id, order_total FROM pg_temp.lab06_cte
    EXCEPT
    SELECT order_id, order_total FROM pg_temp.lab06_main
)
SELECT
    (SELECT COUNT(*) FROM order_totals) AS orders_with_items,
    ROUND((SELECT AVG(order_total) FROM order_totals)::numeric, 2) AS avg_order_total,
    (SELECT COUNT(*) FROM pg_temp.lab06_main) AS main_result_count,
    (SELECT COUNT(*) FROM pg_temp.lab06_cte) AS cte_result_count,
    (SELECT COUNT(*) FROM main_minus_cte) AS main_minus_cte_mismatch,
    (SELECT COUNT(*) FROM cte_minus_main) AS cte_minus_main_mismatch,
    (SELECT COUNT(*) FROM order_totals ot WHERE ot.order_total > ANY (SELECT order_total FROM comparison_set)) AS any_demo_count,
    (SELECT COUNT(*) FROM order_totals ot WHERE ot.order_total > ALL (SELECT order_total FROM comparison_set)) AS all_demo_count;

