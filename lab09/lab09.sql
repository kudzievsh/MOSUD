\pset pager off
\echo '============================================================'
\echo 'LAB 09. Variant 3. Functional dependencies and normalization'
\echo 'Source relation: promo_flat'
\echo '============================================================'

SET search_path TO lab, olist, public;
CREATE SCHEMA IF NOT EXISTS lab;

-- ============================================================
-- 0. Очистка объектов от предыдущего запуска
-- ============================================================
DROP TABLE IF EXISTS lab.nf_3_promo_scope CASCADE;
DROP TABLE IF EXISTS lab.nf_3_products CASCADE;
DROP TABLE IF EXISTS lab.nf_3_sellers CASCADE;
DROP TABLE IF EXISTS lab.nf_3_promotions CASCADE;
DROP TABLE IF EXISTS pg_temp.lab09_flat_sample;

-- ============================================================
-- 1. Плоское исходное отношение для демонстрации
--
-- Исходное отношение:
-- promo_flat(
--   promo_id, promo_name, start_date, end_date,
--   product_id, category_name,
--   seller_id, seller_city,
--   discount
-- )
--
-- Функциональные зависимости из условия:
--   promo_id   -> promo_name, start_date, end_date, discount
--   product_id -> category_name
--   seller_id  -> seller_city
--
-- Потенциальный ключ:
--   (promo_id, product_id, seller_id)
-- ============================================================
CREATE TEMP TABLE lab09_flat_sample AS
WITH
p AS (
    SELECT
        product_id,
        product_category_name AS category_name,
        ROW_NUMBER() OVER (ORDER BY product_id) AS rn
    FROM olist.products
    WHERE product_category_name IS NOT NULL
),
s AS (
    SELECT
        seller_id,
        seller_city,
        ROW_NUMBER() OVER (ORDER BY seller_id) AS rn
    FROM olist.sellers
    WHERE seller_city IS NOT NULL
),
base AS (
    SELECT
        p.rn,
        p.product_id,
        p.category_name,
        s.seller_id,
        s.seller_city
    FROM p
    JOIN s USING (rn)
    WHERE p.rn <= 5
)
SELECT
    CASE
        WHEN rn IN (1,2) THEN 1
        WHEN rn IN (3,4) THEN 2
        ELSE 3
    END::integer AS promo_id,
    CASE
        WHEN rn IN (1,2) THEN 'Normalized Promo A'
        WHEN rn IN (3,4) THEN 'Normalized Promo B'
        ELSE 'Normalized Promo C'
    END::text AS promo_name,
    CASE
        WHEN rn IN (1,2) THEN DATE '2018-06-01'
        WHEN rn IN (3,4) THEN DATE '2018-07-01'
        ELSE DATE '2018-08-01'
    END AS start_date,
    CASE
        WHEN rn IN (1,2) THEN DATE '2018-06-15'
        WHEN rn IN (3,4) THEN DATE '2018-07-20'
        ELSE DATE '2018-08-10'
    END AS end_date,
    product_id,
    category_name,
    seller_id,
    seller_city,
    CASE
        WHEN rn IN (1,2) THEN 10.00
        WHEN rn IN (3,4) THEN 15.00
        ELSE 20.00
    END::numeric(5,2) AS discount
FROM base
ORDER BY rn;

\echo ''
\echo '1. Flat sample: repeated descriptive attributes'
TABLE lab09_flat_sample;

-- ============================================================
-- 2. Декомпозиция до 3НФ / НФБК
--
-- Причина декомпозиции:
-- promo_id, product_id и seller_id являются собственными подмножествами
-- составного потенциального ключа, но каждый из них определяет неключевые атрибуты.
-- Это частичные зависимости, которые создают избыточность данных.
-- ============================================================

CREATE TABLE lab.nf_3_promotions (
    promo_id integer,
    promo_name text NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    discount numeric(5,2) NOT NULL,

    CONSTRAINT pk_nf_3_promotions PRIMARY KEY (promo_id),
    CONSTRAINT ck_nf_3_promotions_dates CHECK (end_date >= start_date),
    CONSTRAINT ck_nf_3_promotions_discount CHECK (discount > 0 AND discount < 100)
);

CREATE TABLE lab.nf_3_products (
    product_id varchar(32),
    category_name text NOT NULL,

    CONSTRAINT pk_nf_3_products PRIMARY KEY (product_id),
    CONSTRAINT fk_nf_3_products_olist_product
        FOREIGN KEY (product_id)
        REFERENCES olist.products(product_id)
);

CREATE TABLE lab.nf_3_sellers (
    seller_id varchar(32),
    seller_city text NOT NULL,

    CONSTRAINT pk_nf_3_sellers PRIMARY KEY (seller_id),
    CONSTRAINT fk_nf_3_sellers_olist_seller
        FOREIGN KEY (seller_id)
        REFERENCES olist.sellers(seller_id)
);

CREATE TABLE lab.nf_3_promo_scope (
    promo_id integer NOT NULL,
    product_id varchar(32) NOT NULL,
    seller_id varchar(32) NOT NULL,

    CONSTRAINT pk_nf_3_promo_scope
        PRIMARY KEY (promo_id, product_id, seller_id),
    CONSTRAINT fk_nf_3_scope_promotion
        FOREIGN KEY (promo_id)
        REFERENCES lab.nf_3_promotions(promo_id),
    CONSTRAINT fk_nf_3_scope_product
        FOREIGN KEY (product_id)
        REFERENCES lab.nf_3_products(product_id),
    CONSTRAINT fk_nf_3_scope_seller
        FOREIGN KEY (seller_id)
        REFERENCES lab.nf_3_sellers(seller_id)
);

-- ============================================================
-- 3. Заполнение нормализованных отношений из плоской таблицы
-- ============================================================
INSERT INTO lab.nf_3_promotions
    (promo_id, promo_name, start_date, end_date, discount)
SELECT DISTINCT
    promo_id, promo_name, start_date, end_date, discount
FROM lab09_flat_sample
ORDER BY promo_id;

INSERT INTO lab.nf_3_products (product_id, category_name)
SELECT DISTINCT product_id, category_name
FROM lab09_flat_sample
ORDER BY product_id;

INSERT INTO lab.nf_3_sellers (seller_id, seller_city)
SELECT DISTINCT seller_id, seller_city
FROM lab09_flat_sample
ORDER BY seller_id;

INSERT INTO lab.nf_3_promo_scope (promo_id, product_id, seller_id)
SELECT promo_id, product_id, seller_id
FROM lab09_flat_sample
ORDER BY promo_id, product_id, seller_id;

\echo ''
\echo '2. Normalized relations'
SELECT * FROM lab.nf_3_promotions ORDER BY promo_id;
SELECT * FROM lab.nf_3_products ORDER BY product_id;
SELECT * FROM lab.nf_3_sellers ORDER BY seller_id;
SELECT * FROM lab.nf_3_promo_scope ORDER BY promo_id, product_id, seller_id;

-- ============================================================
-- 4. Демонстрация устранения дублирования справочных значений
-- ============================================================
\echo ''
\echo '3. Redundancy reduction'
SELECT
    (SELECT COUNT(*) FROM lab09_flat_sample) AS flat_rows,
    (SELECT COUNT(*) FROM lab.nf_3_promotions) AS promotion_rows,
    (SELECT COUNT(*) FROM lab.nf_3_products) AS product_reference_rows,
    (SELECT COUNT(*) FROM lab.nf_3_sellers) AS seller_reference_rows,
    (SELECT COUNT(*) FROM lab.nf_3_promo_scope) AS relationship_rows;

SELECT
    promo_id,
    COUNT(*) AS occurrences_in_flat,
    COUNT(DISTINCT promo_name) AS distinct_names,
    COUNT(DISTINCT discount) AS distinct_discounts
FROM lab09_flat_sample
GROUP BY promo_id
ORDER BY promo_id;

-- ============================================================
-- 5. Проверка декомпозиции без потерь
-- Восстанавливаем promo_flat соединением нормализованных отношений и
-- сравниваем с исходным примером через EXCEPT в обе стороны.
-- ============================================================
\echo ''
\echo '4. Lossless-join check'
WITH reconstructed AS (
    SELECT
        ps.promo_id,
        p.promo_name,
        p.start_date,
        p.end_date,
        ps.product_id,
        pr.category_name,
        ps.seller_id,
        s.seller_city,
        p.discount
    FROM lab.nf_3_promo_scope AS ps
    JOIN lab.nf_3_promotions AS p
      ON p.promo_id = ps.promo_id
    JOIN lab.nf_3_products AS pr
      ON pr.product_id = ps.product_id
    JOIN lab.nf_3_sellers AS s
      ON s.seller_id = ps.seller_id
)
SELECT 'flat EXCEPT reconstructed' AS check_name, COUNT(*) AS mismatch_count
FROM (
    SELECT * FROM lab09_flat_sample
    EXCEPT
    SELECT * FROM reconstructed
) AS d;

WITH reconstructed AS (
    SELECT
        ps.promo_id,
        p.promo_name,
        p.start_date,
        p.end_date,
        ps.product_id,
        pr.category_name,
        ps.seller_id,
        s.seller_city,
        p.discount
    FROM lab.nf_3_promo_scope AS ps
    JOIN lab.nf_3_promotions AS p
      ON p.promo_id = ps.promo_id
    JOIN lab.nf_3_products AS pr
      ON pr.product_id = ps.product_id
    JOIN lab.nf_3_sellers AS s
      ON s.seller_id = ps.seller_id
)
SELECT 'reconstructed EXCEPT flat' AS check_name, COUNT(*) AS mismatch_count
FROM (
    SELECT * FROM reconstructed
    EXCEPT
    SELECT * FROM lab09_flat_sample
) AS d;

-- ============================================================
-- 6. Проверка ограничений целостности
-- ============================================================
\echo ''
\echo '5. PK / FK / UNIQUE constraints'
SELECT
    tc.table_name,
    tc.constraint_name,
    tc.constraint_type
FROM information_schema.table_constraints AS tc
WHERE tc.table_schema = 'lab'
  AND tc.table_name IN (
      'nf_3_promotions',
      'nf_3_products',
      'nf_3_sellers',
      'nf_3_promo_scope'
  )
  AND tc.constraint_type IN ('PRIMARY KEY', 'FOREIGN KEY', 'UNIQUE')
ORDER BY tc.table_name, tc.constraint_type, tc.constraint_name;

-- ============================================================
-- 7. Итоговые результаты для проверки
-- ============================================================
\echo ''
\echo '============================================================'
\echo 'FINAL RESULTS FOR CHECKING'
\echo '============================================================'
WITH reconstructed AS (
    SELECT
        ps.promo_id,
        p.promo_name,
        p.start_date,
        p.end_date,
        ps.product_id,
        pr.category_name,
        ps.seller_id,
        s.seller_city,
        p.discount
    FROM lab.nf_3_promo_scope AS ps
    JOIN lab.nf_3_promotions AS p
      ON p.promo_id = ps.promo_id
    JOIN lab.nf_3_products AS pr
      ON pr.product_id = ps.product_id
    JOIN lab.nf_3_sellers AS s
      ON s.seller_id = ps.seller_id
),
flat_minus_reconstructed AS (
    SELECT * FROM lab09_flat_sample
    EXCEPT
    SELECT * FROM reconstructed
),
reconstructed_minus_flat AS (
    SELECT * FROM reconstructed
    EXCEPT
    SELECT * FROM lab09_flat_sample
)
SELECT
    (SELECT COUNT(*) FROM lab09_flat_sample) AS flat_rows,
    (SELECT COUNT(*) FROM lab.nf_3_promotions) AS promotions_rows,
    (SELECT COUNT(*) FROM lab.nf_3_products) AS products_rows,
    (SELECT COUNT(*) FROM lab.nf_3_sellers) AS sellers_rows,
    (SELECT COUNT(*) FROM lab.nf_3_promo_scope) AS scope_rows,
    (SELECT COUNT(*) FROM flat_minus_reconstructed) AS flat_minus_reconstructed,
    (SELECT COUNT(*) FROM reconstructed_minus_flat) AS reconstructed_minus_flat;
