-- Практическая работа № 3
-- Выборка, проекция, переименование и реляционная алгебра
-- Вариант 3
--
-- Исходное отношение: olist.products
-- Предикат: 1000 <= product_weight_g <= 5000 AND product_photos_qty >= 3
-- Проекция: product_id, category, weight_g, photos_qty
--
-- В исходной схеме используются имена:
--   product_category_name -> category
--   product_weight_g      -> weight_g
--   product_photos_qty    -> photos_qty
--
-- Скрипт только читает данные и создаёт TEMP VIEW в текущем сеансе.
-- Исходные таблицы не изменяются.

\pset pager off
\echo '============================================================'
\echo 'Практическая работа № 3. Вариант 3'
\echo 'products: 1000 <= weight_g <= 5000 AND photos_qty >= 3'
\echo '============================================================'

SET search_path TO olist, public;

-- ============================================================
-- 1. Исходное отношение и используемые атрибуты
-- ============================================================
-- R = products(
--     product_id,
--     product_category_name,
--     product_weight_g,
--     product_photos_qty,
--     ...
-- )
--
-- Используемые атрибуты:
-- product_id, product_category_name, product_weight_g,
-- product_photos_qty.

\echo ''
\echo '1. Исходная таблица products и используемые атрибуты'
SELECT
    COUNT(*) AS products_total,
    COUNT(product_weight_g) AS non_null_weight_g,
    COUNT(product_photos_qty) AS non_null_photos_qty
FROM products;

-- ============================================================
-- 2. Реляционная алгебра
-- ============================================================
-- Основное выражение:
--
-- π_{product_id, product_category_name, product_weight_g, product_photos_qty}
--   (σ_{1000 <= product_weight_g <= 5000 AND product_photos_qty >= 3}(products))
--
-- С переименованием:
--
-- ρ_{category <- product_category_name,
--    weight_g <- product_weight_g,
--    photos_qty <- product_photos_qty}
-- (
--   π_{product_id, product_category_name, product_weight_g, product_photos_qty}
--   (σ_{1000 <= product_weight_g <= 5000 AND product_photos_qty >= 3}(products))
-- )

-- ============================================================
-- 3. SQL-реализация исходного выражения
-- ============================================================
DROP VIEW IF EXISTS pg_temp.lab03_original;
CREATE TEMP VIEW lab03_original AS
SELECT
    product_id,
    product_category_name AS category,
    product_weight_g AS weight_g,
    product_photos_qty AS photos_qty
FROM products
WHERE product_weight_g BETWEEN 1000 AND 5000
  AND product_photos_qty >= 3;

\echo ''
\echo '2. Исходный SQL-вариант: количество строк'
SELECT COUNT(*) AS original_rows
FROM lab03_original;

\echo ''
\echo 'Первые 10 строк результата'
SELECT *
FROM lab03_original
ORDER BY product_id
LIMIT 10;

-- ============================================================
-- 4. Разбиение сложного предиката на две последовательные выборки
-- ============================================================
-- σ_{photos_qty >= 3}(σ_{1000 <= weight_g <= 5000}(products))
-- эквивалентно
-- σ_{1000 <= weight_g <= 5000 AND photos_qty >= 3}(products).

DROP VIEW IF EXISTS pg_temp.lab03_after_weight;
CREATE TEMP VIEW lab03_after_weight AS
SELECT *
FROM products
WHERE product_weight_g BETWEEN 1000 AND 5000;

DROP VIEW IF EXISTS pg_temp.lab03_split_selection;
CREATE TEMP VIEW lab03_split_selection AS
SELECT
    product_id,
    product_category_name AS category,
    product_weight_g AS weight_g,
    product_photos_qty AS photos_qty
FROM lab03_after_weight
WHERE product_photos_qty >= 3;

\echo ''
\echo '3. Последовательные выборки: промежуточное и итоговое число строк'
SELECT
    (SELECT COUNT(*) FROM lab03_after_weight) AS after_weight_filter,
    (SELECT COUNT(*) FROM lab03_split_selection) AS after_both_filters;

\echo ''
\echo 'Проверка эквивалентности исходной и последовательной выборок'
WITH mismatch AS (
    (SELECT * FROM lab03_original
     EXCEPT
     SELECT * FROM lab03_split_selection)
    UNION ALL
    (SELECT * FROM lab03_split_selection
     EXCEPT
     SELECT * FROM lab03_original)
)
SELECT
    COUNT(*) AS mismatch_count,
    COUNT(*) = 0 AS is_equal
FROM mismatch;

-- ============================================================
-- 5. Вариант с ранним исключением ненужных столбцов
-- ============================================================
-- Сначала выполняется проекция только на четыре нужных атрибута,
-- после чего к уменьшенному промежуточному отношению применяются фильтры.

DROP VIEW IF EXISTS pg_temp.lab03_early_projection;
CREATE TEMP VIEW lab03_early_projection AS
SELECT
    product_id,
    product_category_name AS category,
    product_weight_g AS weight_g,
    product_photos_qty AS photos_qty
FROM products;

DROP VIEW IF EXISTS pg_temp.lab03_early_projection_result;
CREATE TEMP VIEW lab03_early_projection_result AS
SELECT
    product_id,
    category,
    weight_g,
    photos_qty
FROM lab03_early_projection
WHERE weight_g BETWEEN 1000 AND 5000
  AND photos_qty >= 3;

\echo ''
\echo '4. Ранняя проекция: проверка эквивалентности'
WITH mismatch AS (
    (SELECT * FROM lab03_original
     EXCEPT
     SELECT * FROM lab03_early_projection_result)
    UNION ALL
    (SELECT * FROM lab03_early_projection_result
     EXCEPT
     SELECT * FROM lab03_original)
)
SELECT
    COUNT(*) AS mismatch_count,
    COUNT(*) = 0 AS is_equal
FROM mismatch;

-- ============================================================
-- 6. Дубликаты в проекции: SELECT и SELECT DISTINCT
-- ============================================================
-- В заданной проекции присутствует product_id. В таблице products
-- product_id является первичным ключом, поэтому две строки результата
-- не могут совпасть по всем четырём проецируемым атрибутам.
-- Следовательно, SELECT и SELECT DISTINCT должны иметь одинаковую
-- мощность результата.

\echo ''
\echo '5. Проверка дубликатов в заданной проекции'
SELECT
    (SELECT COUNT(*)
     FROM lab03_original) AS select_rows,
    (SELECT COUNT(*)
     FROM (
         SELECT DISTINCT product_id, category, weight_g, photos_qty
         FROM lab03_original
     ) AS d) AS distinct_rows,
    (SELECT COUNT(*)
     FROM lab03_original)
    -
    (SELECT COUNT(*)
     FROM (
         SELECT DISTINCT product_id, category, weight_g, photos_qty
         FROM lab03_original
     ) AS d) AS duplicate_excess;

-- Дополнительная иллюстрация: если убрать ключ product_id,
-- дубликаты теоретически уже возможны. Этот запрос не является
-- обязательной частью варианта, а лишь показывает разницу между
-- математической проекцией и SELECT в SQL.
\echo ''
\echo 'Дополнительно: проекция без product_id'
SELECT
    COUNT(*) AS rows_without_product_id,
    COUNT(DISTINCT (category, weight_g, photos_qty)) AS distinct_rows_without_product_id,
    COUNT(*) - COUNT(DISTINCT (category, weight_g, photos_qty)) AS duplicate_excess_without_product_id
FROM lab03_original;

-- ============================================================
-- Итоговый блок для README
-- ============================================================
\echo ''
\echo '============================================================'
\echo 'ИТОГОВЫЕ РЕЗУЛЬТАТЫ ДЛЯ README'
\echo '============================================================'
WITH
original AS (
    SELECT COUNT(*)::bigint AS cnt FROM lab03_original
),
split_mismatch AS (
    SELECT COUNT(*)::bigint AS cnt
    FROM (
        (SELECT * FROM lab03_original
         EXCEPT
         SELECT * FROM lab03_split_selection)
        UNION ALL
        (SELECT * FROM lab03_split_selection
         EXCEPT
         SELECT * FROM lab03_original)
    ) AS q
),
early_mismatch AS (
    SELECT COUNT(*)::bigint AS cnt
    FROM (
        (SELECT * FROM lab03_original
         EXCEPT
         SELECT * FROM lab03_early_projection_result)
        UNION ALL
        (SELECT * FROM lab03_early_projection_result
         EXCEPT
         SELECT * FROM lab03_original)
    ) AS q
),
distinct_result AS (
    SELECT COUNT(*)::bigint AS cnt
    FROM (
        SELECT DISTINCT product_id, category, weight_g, photos_qty
        FROM lab03_original
    ) AS q
),
reduced_projection AS (
    SELECT
        COUNT(*)::bigint AS all_rows,
        COUNT(DISTINCT (category, weight_g, photos_qty))::bigint AS distinct_rows
    FROM lab03_original
)
SELECT
    (SELECT cnt FROM original) AS result_rows,
    (SELECT cnt FROM split_mismatch) AS split_mismatch_count,
    (SELECT cnt FROM early_mismatch) AS early_projection_mismatch_count,
    (SELECT cnt FROM distinct_result) AS distinct_result_rows,
    (SELECT all_rows - distinct_rows FROM reduced_projection) AS duplicate_excess_without_product_id;
