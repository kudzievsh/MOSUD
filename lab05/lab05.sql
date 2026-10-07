\pset pager off
\echo '============================================================'
\echo 'LAB 05. Variant 3. EXISTS and relational division'
\echo 'Target states: BA, PE, CE'
\echo '============================================================'

SET search_path TO olist, public;

-- Docker Desktop containers often have a small /dev/shm.
-- Disable parallel query for this lab so the equivalence checks do not
-- require dynamic shared-memory segments. This changes only the execution
-- plan, not the result of the queries.
SET max_parallel_workers_per_gather = 0;

-- ============================================================
-- Base relation used in the task:
-- delivered orders only, non-NULL product categories only.
-- One row corresponds to category/state/order occurrence.
-- ============================================================
DROP VIEW IF EXISTS pg_temp.lab05_sales;
CREATE TEMP VIEW lab05_sales AS
SELECT DISTINCT
    p.product_category_name AS category,
    c.customer_state,
    o.order_id,
    oi.seller_id
FROM olist.orders AS o
JOIN olist.customers AS c
    ON c.customer_id = o.customer_id
JOIN olist.order_items AS oi
    ON oi.order_id = o.order_id
JOIN olist.products AS p
    ON p.product_id = oi.product_id
WHERE o.order_status = 'delivered'
  AND p.product_category_name IS NOT NULL;

\echo ''
\echo '1. Target states'
WITH target_states(state) AS (
    VALUES ('BA'), ('PE'), ('CE')
)
SELECT * FROM target_states ORDER BY state;

-- ============================================================
-- 2. Relational division using double NOT EXISTS.
-- Meaning: there is no required state for which there is no
-- matching sale of the category.
-- ============================================================
DROP VIEW IF EXISTS pg_temp.lab05_not_exists;
CREATE TEMP VIEW lab05_not_exists AS
WITH target_states(state) AS (
    VALUES ('BA'), ('PE'), ('CE')
),
categories AS (
    SELECT DISTINCT category
    FROM lab05_sales
)
SELECT c.category
FROM categories AS c
WHERE NOT EXISTS (
    SELECT 1
    FROM target_states AS ts
    WHERE NOT EXISTS (
        SELECT 1
        FROM lab05_sales AS s
        WHERE s.category = c.category
          AND s.customer_state = ts.state
    )
);

\echo ''
\echo '2. Double NOT EXISTS result'
SELECT COUNT(*) AS category_count
FROM lab05_not_exists;

SELECT category
FROM lab05_not_exists
ORDER BY category
LIMIT 20;

-- ============================================================
-- 3. The same division using GROUP BY / HAVING COUNT(DISTINCT).
-- The number of matched target states must equal divisor size.
-- ============================================================
DROP VIEW IF EXISTS pg_temp.lab05_group_by;
CREATE TEMP VIEW lab05_group_by AS
WITH target_states(state) AS (
    VALUES ('BA'), ('PE'), ('CE')
)
SELECT s.category
FROM lab05_sales AS s
JOIN target_states AS ts
    ON ts.state = s.customer_state
GROUP BY s.category
HAVING COUNT(DISTINCT s.customer_state) =
       (SELECT COUNT(*) FROM target_states);

\echo ''
\echo '3. GROUP BY / HAVING result'
SELECT COUNT(*) AS category_count
FROM lab05_group_by;

-- ============================================================
-- 4. The same division using EXCEPT inside NOT EXISTS.
-- For a category, target_states EXCEPT states where the category
-- was sold must be empty.
-- ============================================================
DROP VIEW IF EXISTS pg_temp.lab05_except;
CREATE TEMP VIEW lab05_except AS
WITH target_states(state) AS (
    VALUES ('BA'), ('PE'), ('CE')
),
categories AS (
    SELECT DISTINCT category
    FROM lab05_sales
)
SELECT c.category
FROM categories AS c
WHERE NOT EXISTS (
    SELECT state
    FROM target_states
    EXCEPT
    SELECT s.customer_state
    FROM lab05_sales AS s
    WHERE s.category = c.category
);

\echo ''
\echo '4. EXCEPT + NOT EXISTS result'
SELECT COUNT(*) AS category_count
FROM lab05_except;

-- ============================================================
-- 5. Equivalence checks in both directions.
-- All mismatch counts must be 0.
-- ============================================================
\echo ''
\echo '5. Equivalence checks'
SELECT
    'NOT EXISTS vs GROUP BY' AS check_name,
    (
        SELECT COUNT(*)
        FROM (
            (SELECT category FROM lab05_not_exists
             EXCEPT
             SELECT category FROM lab05_group_by)
            UNION ALL
            (SELECT category FROM lab05_group_by
             EXCEPT
             SELECT category FROM lab05_not_exists)
        ) AS d
    ) AS mismatch_count;

SELECT
    'NOT EXISTS vs EXCEPT' AS check_name,
    (
        SELECT COUNT(*)
        FROM (
            (SELECT category FROM lab05_not_exists
             EXCEPT
             SELECT category FROM lab05_except)
            UNION ALL
            (SELECT category FROM lab05_except
             EXCEPT
             SELECT category FROM lab05_not_exists)
        ) AS d
    ) AS mismatch_count;

-- ============================================================
-- 6. Diagnostic table for one found category:
-- category -> state -> number of distinct delivered orders.
-- ============================================================
\echo ''
\echo '6. Diagnostic table for one category'
WITH chosen_category AS (
    SELECT category
    FROM lab05_not_exists
    ORDER BY category
    LIMIT 1
),
target_states(state) AS (
    VALUES ('BA'), ('PE'), ('CE')
)
SELECT
    cc.category,
    ts.state,
    COUNT(DISTINCT s.order_id) AS orders_count
FROM chosen_category AS cc
CROSS JOIN target_states AS ts
LEFT JOIN lab05_sales AS s
    ON s.category = cc.category
   AND s.customer_state = ts.state
GROUP BY cc.category, ts.state
ORDER BY ts.state;

-- ============================================================
-- 7. Empty target_states.
-- Universal condition is vacuously true: for every category,
-- there is no required state that is missing, because there are
-- no required states at all. Therefore the double NOT EXISTS
-- version returns all candidate categories.
-- ============================================================
\echo ''
\echo '7. Empty target_states: universal condition is vacuously true'
WITH target_states(state) AS (
    SELECT NULL::varchar
    WHERE FALSE
),
categories AS (
    SELECT DISTINCT category
    FROM lab05_sales
),
result AS (
    SELECT c.category
    FROM categories AS c
    WHERE NOT EXISTS (
        SELECT 1
        FROM target_states AS ts
        WHERE NOT EXISTS (
            SELECT 1
            FROM lab05_sales AS s
            WHERE s.category = c.category
              AND s.customer_state = ts.state
        )
    )
)
SELECT
    (SELECT COUNT(*) FROM categories) AS all_candidate_categories,
    (SELECT COUNT(*) FROM result) AS result_with_empty_divisor,
    (SELECT COUNT(*) FROM categories) = (SELECT COUNT(*) FROM result) AS all_categories_returned;

-- Important semantic note:
-- A naive INNER JOIN + GROUP BY/HAVING implementation has no groups
-- when target_states is empty, so it returns zero rows. To preserve
-- the mathematical semantics for an empty divisor, use NOT EXISTS / EXCEPT
-- or explicitly handle the empty-divisor case.

-- ============================================================
-- 8. Additional task: sellers who sold to customers from every
-- target state BA, PE, CE.
-- ============================================================
\echo ''
\echo '8. Additional task: sellers covering all target states'
WITH target_states(state) AS (
    VALUES ('BA'), ('PE'), ('CE')
),
sellers AS (
    SELECT DISTINCT seller_id
    FROM lab05_sales
)
SELECT s.seller_id
FROM sellers AS s
WHERE NOT EXISTS (
    SELECT 1
    FROM target_states AS ts
    WHERE NOT EXISTS (
        SELECT 1
        FROM lab05_sales AS x
        WHERE x.seller_id = s.seller_id
          AND x.customer_state = ts.state
    )
)
ORDER BY s.seller_id
LIMIT 50;

\echo ''
\echo 'Seller count covering all target states'
WITH target_states(state) AS (
    VALUES ('BA'), ('PE'), ('CE')
),
sellers AS (
    SELECT DISTINCT seller_id
    FROM lab05_sales
),
result AS (
    SELECT s.seller_id
    FROM sellers AS s
    WHERE NOT EXISTS (
        SELECT 1
        FROM target_states AS ts
        WHERE NOT EXISTS (
            SELECT 1
            FROM lab05_sales AS x
            WHERE x.seller_id = s.seller_id
              AND x.customer_state = ts.state
        )
    )
)
SELECT COUNT(*) AS seller_count
FROM result;

-- ============================================================
-- Final compact block for checking / README if needed.
-- ============================================================
\echo ''
\echo '============================================================'
\echo 'FINAL RESULTS FOR CHECKING'
\echo '============================================================'
SELECT
    (SELECT COUNT(*) FROM lab05_not_exists) AS not_exists_categories,
    (SELECT COUNT(*) FROM lab05_group_by) AS group_by_categories,
    (SELECT COUNT(*) FROM lab05_except) AS except_categories,
    (
        SELECT COUNT(*)
        FROM (
            (SELECT category FROM lab05_not_exists
             EXCEPT
             SELECT category FROM lab05_group_by)
            UNION ALL
            (SELECT category FROM lab05_group_by
             EXCEPT
             SELECT category FROM lab05_not_exists)
        ) AS d
    ) AS mismatch_not_exists_group_by,
    (
        SELECT COUNT(*)
        FROM (
            (SELECT category FROM lab05_not_exists
             EXCEPT
             SELECT category FROM lab05_except)
            UNION ALL
            (SELECT category FROM lab05_except
             EXCEPT
             SELECT category FROM lab05_not_exists)
        ) AS d
    ) AS mismatch_not_exists_except;
