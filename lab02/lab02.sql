-- Практическая работа № 2
-- «Множества и мультимножества в SQL»
-- Вариант 3: X = RS, Y = SC
-- База данных: olist, схема: olist
-- Учитываются только заказы со статусом delivered.

-- -----------------------------------------------------------------------------
-- 0. Исходные отношения A и B
-- -----------------------------------------------------------------------------
-- A: product_id товаров, которые покупали клиенты штата RS.
-- B: product_id товаров, которые покупали клиенты штата SC.
--
-- A_raw и B_raw намеренно сохраняют повторы: один и тот же товар может встречаться
-- в нескольких позициях/заказах. A и B ниже будут рассматриваться как множества,
-- то есть через DISTINCT или обычные UNION / INTERSECT / EXCEPT.

CREATE OR REPLACE TEMP VIEW lab02_a_raw AS
SELECT oi.product_id
FROM olist.customers AS c
JOIN olist.orders AS o
    ON o.customer_id = c.customer_id
JOIN olist.order_items AS oi
    ON oi.order_id = o.order_id
WHERE c.customer_state = 'RS'
  AND o.order_status = 'delivered';

CREATE OR REPLACE TEMP VIEW lab02_b_raw AS
SELECT oi.product_id
FROM olist.customers AS c
JOIN olist.orders AS o
    ON o.customer_id = c.customer_id
JOIN olist.order_items AS oi
    ON oi.order_id = o.order_id
WHERE c.customer_state = 'SC'
  AND o.order_status = 'delivered';

CREATE OR REPLACE TEMP VIEW lab02_a AS
SELECT DISTINCT product_id
FROM lab02_a_raw;

CREATE OR REPLACE TEMP VIEW lab02_b AS
SELECT DISTINCT product_id
FROM lab02_b_raw;

-- 1. Для A и B: count(*) и count(DISTINCT product_id).
SELECT
    'A (RS)' AS relation_name,
    COUNT(*) AS row_count,
    COUNT(DISTINCT product_id) AS distinct_product_count
FROM lab02_a_raw
UNION ALL
SELECT
    'B (SC)' AS relation_name,
    COUNT(*) AS row_count,
    COUNT(DISTINCT product_id) AS distinct_product_count
FROM lab02_b_raw
ORDER BY relation_name;

-- -----------------------------------------------------------------------------
-- 2. A ∪ B: UNION и UNION ALL
-- -----------------------------------------------------------------------------
-- UNION удаляет одинаковые строки и возвращает множество product_id.
-- UNION ALL сохраняет все вхождения и поэтому может вернуть больше строк.

CREATE OR REPLACE TEMP VIEW lab02_union AS
SELECT product_id FROM lab02_a_raw
UNION
SELECT product_id FROM lab02_b_raw;

CREATE OR REPLACE TEMP VIEW lab02_union_all AS
SELECT product_id FROM lab02_a_raw
UNION ALL
SELECT product_id FROM lab02_b_raw;

SELECT 'UNION' AS operation, COUNT(*) AS row_count
FROM lab02_union
UNION ALL
SELECT 'UNION ALL' AS operation, COUNT(*) AS row_count
FROM lab02_union_all
ORDER BY operation;

-- Количество «лишних» строк, возникающих из-за повторов при UNION ALL.
SELECT
    COUNT(*) AS union_all_rows,
    COUNT(DISTINCT product_id) AS union_all_distinct_products,
    COUNT(*) - COUNT(DISTINCT product_id) AS duplicate_excess
FROM lab02_union_all;

-- -----------------------------------------------------------------------------
-- 3. A ∩ B через INTERSECT
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TEMP VIEW lab02_intersection AS
SELECT product_id FROM lab02_a_raw
INTERSECT
SELECT product_id FROM lab02_b_raw;

SELECT COUNT(*) AS intersection_cardinality
FROM lab02_intersection;

-- Небольшой фрагмент результата для визуальной проверки.
SELECT product_id
FROM lab02_intersection
ORDER BY product_id
LIMIT 10;

-- -----------------------------------------------------------------------------
-- 4. Разности A − B и B − A через EXCEPT
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TEMP VIEW lab02_a_minus_b AS
SELECT product_id FROM lab02_a_raw
EXCEPT
SELECT product_id FROM lab02_b_raw;

CREATE OR REPLACE TEMP VIEW lab02_b_minus_a AS
SELECT product_id FROM lab02_b_raw
EXCEPT
SELECT product_id FROM lab02_a_raw;

SELECT 'A - B' AS operation, COUNT(*) AS row_count
FROM lab02_a_minus_b
UNION ALL
SELECT 'B - A' AS operation, COUNT(*) AS row_count
FROM lab02_b_minus_a
ORDER BY operation;

-- -----------------------------------------------------------------------------
-- 5. Проверка коммутативности объединения и пересечения
-- -----------------------------------------------------------------------------
-- Для равных множеств разность в обе стороны должна быть пустой.

WITH
ab AS (
    SELECT product_id FROM lab02_a
    UNION
    SELECT product_id FROM lab02_b
),
ba AS (
    SELECT product_id FROM lab02_b
    UNION
    SELECT product_id FROM lab02_a
),
diff AS (
    (SELECT product_id FROM ab EXCEPT SELECT product_id FROM ba)
    UNION ALL
    (SELECT product_id FROM ba EXCEPT SELECT product_id FROM ab)
)
SELECT
    'UNION commutativity' AS check_name,
    COUNT(*) AS mismatch_count,
    COUNT(*) = 0 AS is_equal
FROM diff;

WITH
ab AS (
    SELECT product_id FROM lab02_a
    INTERSECT
    SELECT product_id FROM lab02_b
),
ba AS (
    SELECT product_id FROM lab02_b
    INTERSECT
    SELECT product_id FROM lab02_a
),
diff AS (
    (SELECT product_id FROM ab EXCEPT SELECT product_id FROM ba)
    UNION ALL
    (SELECT product_id FROM ba EXCEPT SELECT product_id FROM ab)
)
SELECT
    'INTERSECT commutativity' AS check_name,
    COUNT(*) AS mismatch_count,
    COUNT(*) = 0 AS is_equal
FROM diff;

-- -----------------------------------------------------------------------------
-- 6. Разность некоммутативна
-- -----------------------------------------------------------------------------
-- Проверяем, совпадают ли A − B и B − A. Для данного набора данных ожидается false.
WITH diff AS (
    (SELECT product_id FROM lab02_a_minus_b
     EXCEPT
     SELECT product_id FROM lab02_b_minus_a)
    UNION ALL
    (SELECT product_id FROM lab02_b_minus_a
     EXCEPT
     SELECT product_id FROM lab02_a_minus_b)
)
SELECT
    'Difference commutativity' AS check_name,
    COUNT(*) AS mismatch_count,
    COUNT(*) = 0 AS is_equal
FROM diff;

-- -----------------------------------------------------------------------------
-- 7. Пересечение без INTERSECT: EXISTS
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TEMP VIEW lab02_intersection_exists AS
SELECT DISTINCT a.product_id
FROM lab02_a_raw AS a
WHERE EXISTS (
    SELECT 1
    FROM lab02_b_raw AS b
    WHERE b.product_id = a.product_id
);

SELECT COUNT(*) AS intersection_exists_cardinality
FROM lab02_intersection_exists;

-- Доказываем эквивалентность INTERSECT и EXISTS сравнением в обе стороны.
WITH diff AS (
    (SELECT product_id FROM lab02_intersection
     EXCEPT
     SELECT product_id FROM lab02_intersection_exists)
    UNION ALL
    (SELECT product_id FROM lab02_intersection_exists
     EXCEPT
     SELECT product_id FROM lab02_intersection)
)
SELECT
    'INTERSECT vs EXISTS' AS check_name,
    COUNT(*) AS mismatch_count,
    COUNT(*) = 0 AS is_equal
FROM diff;

-- -----------------------------------------------------------------------------
-- 8. Намеренная демонстрация дубликатов
-- -----------------------------------------------------------------------------
-- Здесь DISTINCT не используется, а UNION заменён на UNION ALL.
-- Поэтому один product_id может встретиться много раз.
SELECT
    product_id,
    COUNT(*) AS occurrences
FROM lab02_union_all
GROUP BY product_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC, product_id
LIMIT 20;

-- -----------------------------------------------------------------------------
-- 9. Множество и мультимножество: итоговый комментарий
-- -----------------------------------------------------------------------------
-- В PostgreSQL обычные UNION, INTERSECT и EXCEPT устраняют повторяющиеся строки
-- и в данной работе соответствуют операциям над множествами.
-- SELECT без DISTINCT может сохранять дубликаты, поэтому его результат в общем
-- случае является мультимножеством. UNION ALL также сохраняет все повторения.
-- В PostgreSQL существуют INTERSECT ALL и EXCEPT ALL, которые также учитывают
-- кратности строк и тем самым имеют мультимножественную семантику.
-- Порядок строк не является свойством отношения: он гарантируется только ORDER BY.

-- -----------------------------------------------------------------------------
-- 10. ИТОГОВЫЕ МОЩНОСТИ ДЛЯ README
-- -----------------------------------------------------------------------------
-- Пришлите эту строку после запуска: по ней можно заполнить lab02/README.md.
SELECT
    (SELECT COUNT(*) FROM lab02_a_raw) AS a_rows_with_duplicates,
    (SELECT COUNT(*) FROM lab02_a) AS a_cardinality,
    (SELECT COUNT(*) FROM lab02_b_raw) AS b_rows_with_duplicates,
    (SELECT COUNT(*) FROM lab02_b) AS b_cardinality,
    (SELECT COUNT(*) FROM lab02_union) AS union_cardinality,
    (SELECT COUNT(*) FROM lab02_intersection) AS intersection_cardinality,
    (SELECT COUNT(*) FROM lab02_a_minus_b) AS a_minus_b_cardinality,
    (SELECT COUNT(*) FROM lab02_b_minus_a) AS b_minus_a_cardinality,
    (SELECT COUNT(*) FROM lab02_union_all) AS union_all_rows,
    (SELECT COUNT(*) FROM lab02_union_all)
      - (SELECT COUNT(DISTINCT product_id) FROM lab02_union_all) AS union_all_duplicate_excess;
