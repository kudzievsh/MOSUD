\pset pager off
\echo '============================================================'
\echo 'Практическая работа №11. Вариант 3'
\echo 'Представления, CTE и рекурсивные запросы'
\echo 'Корневой штат: MG'
\echo '============================================================'

SET search_path TO lab, olist, public;
SET max_parallel_workers_per_gather = 0;

CREATE SCHEMA IF NOT EXISTS lab;

-- ============================================================
-- 0. Очистка объектов предыдущего запуска
-- ============================================================
DROP MATERIALIZED VIEW IF EXISTS lab.mv_monthly_state_sales;
DROP VIEW IF EXISTS lab.v_order_summary;
DROP TABLE IF EXISTS lab.geo_tree;

-- ============================================================
-- 1. Обычное представление v_order_summary
-- Одна строка на заказ: штат покупателя, количество позиций
-- и общая стоимость позиций вместе с доставкой.
-- LEFT JOIN сохраняет и те заказы, у которых вдруг нет позиций.
-- ============================================================
CREATE VIEW lab.v_order_summary AS
SELECT
    o.order_id,
    o.customer_id,
    c.customer_state,
    o.order_purchase_timestamp,
    COUNT(oi.order_item_id) AS items_count,
    ROUND(COALESCE(SUM(oi.price + oi.freight_value), 0)::numeric, 2) AS order_total
FROM olist.orders AS o
JOIN olist.customers AS c
    ON c.customer_id = o.customer_id
LEFT JOIN olist.order_items AS oi
    ON oi.order_id = o.order_id
GROUP BY
    o.order_id,
    o.customer_id,
    c.customer_state,
    o.order_purchase_timestamp;

\echo ''
\echo '1. Проверка lab.v_order_summary'
SELECT
    COUNT(*) AS view_rows,
    COUNT(DISTINCT order_id) AS distinct_orders,
    ROUND(SUM(order_total)::numeric, 2) AS total_price_plus_freight
FROM lab.v_order_summary;

SELECT *
FROM lab.v_order_summary
ORDER BY order_total DESC, order_id
LIMIT 10;

-- ============================================================
-- 2. Материализованное представление mv_monthly_state_sales
-- Хранит физически агрегат: месяц + штат -> число заказов и сумма.
-- В отличие от обычного VIEW, результат MATERIALIZED VIEW
-- обновляется только после REFRESH MATERIALIZED VIEW.
-- ============================================================
CREATE MATERIALIZED VIEW lab.mv_monthly_state_sales AS
SELECT
    date_trunc('month', order_purchase_timestamp)::date AS sales_month,
    customer_state,
    COUNT(*) AS orders_count,
    ROUND(SUM(order_total)::numeric, 2) AS sales_total
FROM lab.v_order_summary
GROUP BY
    date_trunc('month', order_purchase_timestamp)::date,
    customer_state;

-- Команда обновления материализованного представления.
REFRESH MATERIALIZED VIEW lab.mv_monthly_state_sales;

\echo ''
\echo '2. Проверка lab.mv_monthly_state_sales'
SELECT
    COUNT(*) AS monthly_state_rows,
    MIN(sales_month) AS first_month,
    MAX(sales_month) AS last_month,
    ROUND(SUM(sales_total)::numeric, 2) AS total_sales
FROM lab.mv_monthly_state_sales;

SELECT *
FROM lab.mv_monthly_state_sales
ORDER BY sales_month DESC, sales_total DESC
LIMIT 10;

-- ============================================================
-- 3. Аналитический запрос, разбитый минимум на три CTE
-- monthly_sales    -> продажи по месяцам и штатам;
-- state_totals     -> итог по каждому штату;
-- ranked_states    -> место штата по общей сумме продаж.
-- ============================================================
\echo ''
\echo '3. Аналитический запрос через три именованных CTE'
WITH
monthly_sales AS (
    SELECT
        sales_month,
        customer_state,
        orders_count,
        sales_total
    FROM lab.mv_monthly_state_sales
),
state_totals AS (
    SELECT
        customer_state,
        SUM(orders_count) AS total_orders,
        ROUND(SUM(sales_total)::numeric, 2) AS total_sales,
        ROUND(AVG(sales_total)::numeric, 2) AS avg_monthly_sales
    FROM monthly_sales
    GROUP BY customer_state
),
ranked_states AS (
    SELECT
        customer_state,
        total_orders,
        total_sales,
        avg_monthly_sales,
        DENSE_RANK() OVER (ORDER BY total_sales DESC) AS sales_rank
    FROM state_totals
)
SELECT
    customer_state,
    total_orders,
    total_sales,
    avg_monthly_sales,
    sales_rank
FROM ranked_states
ORDER BY sales_rank, customer_state
LIMIT 10;

-- ============================================================
-- 4. Иерархия lab.geo_tree: BR -> штат -> город
-- Для каждого штата добавляются не более 20 городов с наибольшим
-- числом клиентов. Связь parent_id является самоссылочным FK.
-- ============================================================
CREATE TABLE lab.geo_tree (
    node_id   text CONSTRAINT pk_geo_tree PRIMARY KEY,
    parent_id text,
    node_type text NOT NULL,
    node_name text NOT NULL,
    CONSTRAINT fk_geo_tree_parent
        FOREIGN KEY (parent_id)
        REFERENCES lab.geo_tree(node_id),
    CONSTRAINT ck_geo_tree_node_type
        CHECK (node_type IN ('country', 'state', 'city'))
);

INSERT INTO lab.geo_tree(node_id, parent_id, node_type, node_name)
VALUES ('BR', NULL, 'country', 'Brazil');

INSERT INTO lab.geo_tree(node_id, parent_id, node_type, node_name)
SELECT
    'ST:' || c.customer_state,
    'BR',
    'state',
    c.customer_state
FROM olist.customers AS c
WHERE c.customer_state IS NOT NULL
GROUP BY c.customer_state;

WITH city_counts AS (
    SELECT
        c.customer_state,
        c.customer_city,
        COUNT(*) AS customers_count
    FROM olist.customers AS c
    WHERE c.customer_state IS NOT NULL
      AND c.customer_city IS NOT NULL
    GROUP BY c.customer_state, c.customer_city
),
ranked_cities AS (
    SELECT
        customer_state,
        customer_city,
        customers_count,
        ROW_NUMBER() OVER (
            PARTITION BY customer_state
            ORDER BY customers_count DESC, customer_city
        ) AS rn
    FROM city_counts
)
INSERT INTO lab.geo_tree(node_id, parent_id, node_type, node_name)
SELECT
    'CT:' || customer_state || ':' || customer_city,
    'ST:' || customer_state,
    'city',
    customer_city
FROM ranked_cities
WHERE rn <= 20;

\echo ''
\echo '4. Проверка иерархии lab.geo_tree'
SELECT
    node_type,
    COUNT(*) AS nodes_count
FROM lab.geo_tree
GROUP BY node_type
ORDER BY node_type;

-- ============================================================
-- 5. Прямой рекурсивный запрос для варианта 3: корень ST:MG
-- Базовая часть помещает корневой штат MG в результат.
-- Рекурсивная часть добавляет детей текущих узлов.
-- path_ids используется также как защита от возможного цикла.
-- ============================================================
\echo ''
\echo '5. Поддерево штата MG'
WITH RECURSIVE subtree AS (
    SELECT
        0 AS depth,
        g.node_id,
        g.parent_id,
        g.node_name,
        ARRAY[g.node_id]::text[] AS path_ids,
        g.node_name::text AS path
    FROM lab.geo_tree AS g
    WHERE g.node_id = 'ST:MG'

    UNION ALL

    SELECT
        st.depth + 1,
        child.node_id,
        child.parent_id,
        child.node_name,
        st.path_ids || child.node_id,
        st.path || ' -> ' || child.node_name
    FROM subtree AS st
    JOIN lab.geo_tree AS child
        ON child.parent_id = st.node_id
    WHERE NOT child.node_id = ANY(st.path_ids)
)
SELECT
    depth,
    node_id,
    path,
    node_name
FROM subtree
ORDER BY depth, node_name;

-- ============================================================
-- 6. Обратная рекурсия: от city-node Belo Horizonte до BR
-- На каждом шаге рекурсивная часть переходит к parent_id.
-- ============================================================
\echo ''
\echo '6. Цепочка предков: Belo Horizonte -> MG -> Brazil'
WITH RECURSIVE ancestors AS (
    SELECT
        0 AS depth,
        g.node_id,
        g.parent_id,
        g.node_name,
        ARRAY[g.node_id]::text[] AS path_ids,
        g.node_name::text AS path
    FROM lab.geo_tree AS g
    WHERE g.node_id = 'CT:MG:belo horizonte'

    UNION ALL

    SELECT
        a.depth + 1,
        parent.node_id,
        parent.parent_id,
        parent.node_name,
        a.path_ids || parent.node_id,
        a.path || ' -> ' || parent.node_name
    FROM ancestors AS a
    JOIN lab.geo_tree AS parent
        ON parent.node_id = a.parent_id
    WHERE NOT parent.node_id = ANY(a.path_ids)
)
SELECT
    depth,
    node_id,
    path,
    node_name
FROM ancestors
ORDER BY depth;

-- ============================================================
-- 7. Количество потомков каждого state-node
-- Рекурсивный CTE позволяет считать потомков не только первого
-- уровня, поэтому запрос останется корректным и при углублении дерева.
-- ============================================================
\echo ''
\echo '7. Количество потомков каждого штата'
WITH RECURSIVE descendants AS (
    SELECT
        state.node_id AS state_node_id,
        child.node_id AS descendant_id
    FROM lab.geo_tree AS state
    JOIN lab.geo_tree AS child
        ON child.parent_id = state.node_id
    WHERE state.node_type = 'state'

    UNION ALL

    SELECT
        d.state_node_id,
        child.node_id
    FROM descendants AS d
    JOIN lab.geo_tree AS child
        ON child.parent_id = d.descendant_id
)
SELECT
    state.node_id,
    state.node_name,
    COUNT(d.descendant_id) AS descendants_count
FROM lab.geo_tree AS state
LEFT JOIN descendants AS d
    ON d.state_node_id = state.node_id
WHERE state.node_type = 'state'
GROUP BY state.node_id, state.node_name
ORDER BY descendants_count DESC, state.node_name;

-- ============================================================
-- 8. Дополнительно: искусственный цикл и защита от него
-- Создаём временную копию дерева без ограничений и замыкаем цикл:
-- BR -> ST:MG -> BR.
-- В рекурсивном запросе массив path_ids хранит уже посещённые узлы.
-- Условие NOT node_id = ANY(path_ids) запрещает повторный вход в узел.
-- ============================================================
DROP TABLE IF EXISTS pg_temp.geo_tree_cycle;
CREATE TEMP TABLE geo_tree_cycle AS
SELECT * FROM lab.geo_tree;

UPDATE geo_tree_cycle
SET parent_id = 'ST:MG'
WHERE node_id = 'BR';

\echo ''
\echo '8. Проверка защиты рекурсии от искусственного цикла'
WITH RECURSIVE safe_walk AS (
    SELECT
        0 AS depth,
        g.node_id,
        g.parent_id,
        ARRAY[g.node_id]::text[] AS path_ids
    FROM geo_tree_cycle AS g
    WHERE g.node_id = 'BR'

    UNION ALL

    SELECT
        w.depth + 1,
        child.node_id,
        child.parent_id,
        w.path_ids || child.node_id
    FROM safe_walk AS w
    JOIN geo_tree_cycle AS child
        ON child.parent_id = w.node_id
    WHERE NOT child.node_id = ANY(w.path_ids)
)
SELECT
    COUNT(*) AS safe_walk_rows,
    MAX(depth) AS max_depth,
    COUNT(*) FILTER (WHERE node_id = 'BR') AS br_occurrences
FROM safe_walk;

-- ============================================================
-- Итоговый контрольный блок
-- ============================================================
\echo ''
\echo '============================================================'
\echo 'ИТОГОВЫЕ РЕЗУЛЬТАТЫ ДЛЯ ПРОВЕРКИ'
\echo '============================================================'
WITH RECURSIVE
mg_subtree AS (
    SELECT
        g.node_id,
        ARRAY[g.node_id]::text[] AS path_ids
    FROM lab.geo_tree AS g
    WHERE g.node_id = 'ST:MG'

    UNION ALL

    SELECT
        child.node_id,
        m.path_ids || child.node_id
    FROM mg_subtree AS m
    JOIN lab.geo_tree AS child
        ON child.parent_id = m.node_id
    WHERE NOT child.node_id = ANY(m.path_ids)
),
mg_ancestors AS (
    SELECT
        g.node_id,
        g.parent_id,
        ARRAY[g.node_id]::text[] AS path_ids
    FROM lab.geo_tree AS g
    WHERE g.node_id = 'CT:MG:belo horizonte'

    UNION ALL

    SELECT
        parent.node_id,
        parent.parent_id,
        a.path_ids || parent.node_id
    FROM mg_ancestors AS a
    JOIN lab.geo_tree AS parent
        ON parent.node_id = a.parent_id
    WHERE NOT parent.node_id = ANY(a.path_ids)
)
SELECT
    (SELECT COUNT(*) FROM lab.v_order_summary) AS order_summary_rows,
    (SELECT COUNT(*) FROM lab.mv_monthly_state_sales) AS monthly_state_rows,
    (SELECT COUNT(*) FROM lab.geo_tree) AS geo_tree_nodes,
    (SELECT COUNT(*) FROM lab.geo_tree WHERE node_type = 'state') AS state_nodes,
    (SELECT COUNT(*) FROM lab.geo_tree WHERE node_type = 'city') AS city_nodes,
    (SELECT COUNT(*) FROM mg_subtree) AS mg_subtree_nodes,
    (SELECT COUNT(*) FROM mg_ancestors) AS belo_horizonte_ancestor_chain;
