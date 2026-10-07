\pset pager off
\echo '============================================================'
\echo 'LAB 07. NULL, three-valued logic and data quality'
\echo '============================================================'

SET search_path TO olist, public;
SET max_parallel_workers_per_gather = 0;

-- ============================================================
-- 1. NULL counts for potentially optional columns.
-- ============================================================
\echo ''
\echo '1A. NULL profile: orders'
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE order_approved_at IS NULL) AS null_order_approved_at,
    COUNT(*) FILTER (WHERE order_delivered_carrier_date IS NULL) AS null_order_delivered_carrier_date,
    COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS null_order_delivered_customer_date,
    COUNT(*) FILTER (WHERE order_estimated_delivery_date IS NULL) AS null_order_estimated_delivery_date
FROM olist.orders;

\echo ''
\echo '1B. NULL profile: products'
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE product_category_name IS NULL) AS null_category,
    COUNT(*) FILTER (WHERE product_name_lenght IS NULL) AS null_name_length,
    COUNT(*) FILTER (WHERE product_description_lenght IS NULL) AS null_description_length,
    COUNT(*) FILTER (WHERE product_photos_qty IS NULL) AS null_photos_qty,
    COUNT(*) FILTER (WHERE product_weight_g IS NULL) AS null_weight_g,
    COUNT(*) FILTER (WHERE product_length_cm IS NULL) AS null_length_cm,
    COUNT(*) FILTER (WHERE product_height_cm IS NULL) AS null_height_cm,
    COUNT(*) FILTER (WHERE product_width_cm IS NULL) AS null_width_cm
FROM olist.products;

\echo ''
\echo '1C. NULL profile: order_reviews'
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE review_comment_title IS NULL) AS null_comment_title,
    COUNT(*) FILTER (WHERE review_comment_message IS NULL) AS null_comment_message,
    COUNT(*) FILTER (WHERE review_creation_date IS NULL) AS null_creation_date,
    COUNT(*) FILTER (WHERE review_answer_timestamp IS NULL) AS null_answer_timestamp
FROM olist.order_reviews;

-- ============================================================
-- 2. COUNT(*) vs COUNT(nullable_column).
-- COUNT(column) ignores NULL values.
-- ============================================================
\echo ''
\echo '2. COUNT(*) versus COUNT(order_delivered_customer_date)'
SELECT
    COUNT(*) AS count_all_orders,
    COUNT(order_delivered_customer_date) AS count_non_null_delivery_dates,
    COUNT(*) - COUNT(order_delivered_customer_date) AS difference_due_to_null
FROM olist.orders;

-- ============================================================
-- 3. = NULL and <> NULL produce UNKNOWN, not TRUE.
-- Correct checks use IS NULL / IS NOT NULL.
-- ============================================================
\echo ''
\echo '3. Wrong NULL comparisons versus correct predicates'
SELECT
    (SELECT COUNT(*) FROM olist.orders WHERE order_delivered_customer_date = NULL) AS equals_null_rows,
    (SELECT COUNT(*) FROM olist.orders WHERE order_delivered_customer_date <> NULL) AS not_equals_null_rows,
    (SELECT COUNT(*) FROM olist.orders WHERE order_delivered_customer_date IS NULL) AS is_null_rows,
    (SELECT COUNT(*) FROM olist.orders WHERE order_delivered_customer_date IS NOT NULL) AS is_not_null_rows;

-- ============================================================
-- 4. IS DISTINCT FROM treats NULL as a comparable state.
-- ============================================================
\echo ''
\echo '4. IS DISTINCT FROM demonstration'
SELECT
    NULL::text = NULL::text AS null_equals_null,
    NULL::text IS DISTINCT FROM NULL::text AS null_distinct_from_null,
    NULL::text IS DISTINCT FROM 'known'::text AS null_distinct_from_value,
    'known'::text IS DISTINCT FROM 'known'::text AS equal_values_distinct;

-- ============================================================
-- 5. NOT IN versus NOT EXISTS when the subquery contains NULL.
-- temp_ids contains one real order_id and one NULL.
-- ============================================================
\echo ''
\echo '5. NOT IN versus NOT EXISTS with NULL in the subquery'
DROP TABLE IF EXISTS pg_temp.temp_ids;
CREATE TEMP TABLE temp_ids(id text);

INSERT INTO temp_ids(id)
SELECT order_id
FROM olist.orders
ORDER BY order_id
LIMIT 1;

INSERT INTO temp_ids(id) VALUES (NULL);

TABLE temp_ids;

SELECT
    (SELECT COUNT(*)
     FROM olist.orders o
     WHERE o.order_id NOT IN (SELECT id FROM temp_ids)) AS not_in_count,
    (SELECT COUNT(*)
     FROM olist.orders o
     WHERE NOT EXISTS (
         SELECT 1
         FROM temp_ids t
         WHERE t.id = o.order_id
     )) AS not_exists_count;

-- ============================================================
-- 6. LEFT JOIN predicate in ON versus WHERE.
-- In ON: all orders remain, reviews with score < 4 simply do not match.
-- In WHERE: rows with no matching review are removed, so the LEFT JOIN
-- behaves like an INNER JOIN for this predicate.
-- ============================================================
\echo ''
\echo '6. LEFT JOIN: filter in ON versus filter in WHERE'
SELECT
    COUNT(DISTINCT o.order_id) AS distinct_orders_filter_in_on,
    COUNT(r.review_id) AS matched_reviews_score_ge_4
FROM olist.orders o
LEFT JOIN olist.order_reviews r
    ON r.order_id = o.order_id
   AND r.review_score >= 4;

SELECT
    COUNT(DISTINCT o.order_id) AS distinct_orders_filter_in_where,
    COUNT(r.review_id) AS matched_reviews_score_ge_4
FROM olist.orders o
LEFT JOIN olist.order_reviews r
    ON r.order_id = o.order_id
WHERE r.review_score >= 4;

-- ============================================================
-- 7. COALESCE and NULLIF.
-- COALESCE supplies text for missing comments.
-- NULLIF protects division from a zero denominator.
-- ============================================================
\echo ''
\echo '7A. COALESCE for missing review text'
SELECT
    review_id,
    review_score,
    COALESCE(review_comment_message, '[no comment]') AS safe_comment
FROM olist.order_reviews
ORDER BY review_id
LIMIT 10;

\echo ''
\echo '7B. NULLIF for safe division'
SELECT
    COUNT(*) AS total_reviews,
    COUNT(review_comment_message) AS reviews_with_text,
    ROUND(
        100.0 * COUNT(review_comment_message) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_reviews_with_text
FROM olist.order_reviews;

-- ============================================================
-- 8. Mini data-quality profile.
-- ============================================================
\echo ''
\echo '8. Mini data-quality profile'
SELECT
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL)
        / NULLIF(COUNT(*), 0),
        2
    ) AS pct_orders_without_actual_delivery_date
FROM olist.orders;

SELECT
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE product_category_name IS NULL)
        / NULLIF(COUNT(*), 0),
        2
    ) AS pct_products_without_category
FROM olist.products;

SELECT
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE review_comment_message IS NULL)
        / NULLIF(COUNT(*), 0),
        2
    ) AS pct_reviews_without_text
FROM olist.order_reviews;

-- ============================================================
-- 9. Interpretation.
-- Natural NULL example: review_comment_message.
-- A buyer may legitimately leave only a numeric score and no text.
-- Potential data-quality NULL example: product_category_name.
-- A catalog product normally should have a category; missing category reduces
-- analytical usefulness and is more plausibly a completeness problem.
-- ============================================================
\echo ''
\echo '9. Natural NULL vs potential data-quality NULL'
SELECT
    (SELECT COUNT(*) FROM olist.order_reviews WHERE review_comment_message IS NULL) AS natural_null_review_text,
    (SELECT COUNT(*) FROM olist.products WHERE product_category_name IS NULL) AS potential_quality_null_category;

-- ============================================================
-- 10. Final summary for checking.
-- ============================================================
\echo ''
\echo '============================================================'
\echo 'FINAL RESULTS FOR CHECKING'
\echo '============================================================'
SELECT
    (SELECT COUNT(*) FROM olist.orders) AS orders_total,
    (SELECT COUNT(*) FROM olist.orders WHERE order_delivered_customer_date IS NULL) AS orders_without_delivery_date,
    (SELECT COUNT(*) FROM olist.products WHERE product_category_name IS NULL) AS products_without_category,
    (SELECT COUNT(*) FROM olist.order_reviews WHERE review_comment_message IS NULL) AS reviews_without_text,
    (SELECT COUNT(*) FROM olist.orders o WHERE o.order_id NOT IN (SELECT id FROM temp_ids)) AS not_in_count_with_null,
    (SELECT COUNT(*) FROM olist.orders o WHERE NOT EXISTS (SELECT 1 FROM temp_ids t WHERE t.id = o.order_id)) AS not_exists_count_with_null,
    (SELECT COUNT(DISTINCT o.order_id)
     FROM olist.orders o
     LEFT JOIN olist.order_reviews r
       ON r.order_id = o.order_id AND r.review_score >= 4) AS orders_left_join_filter_on,
    (SELECT COUNT(DISTINCT o.order_id)
     FROM olist.orders o
     LEFT JOIN olist.order_reviews r
       ON r.order_id = o.order_id
     WHERE r.review_score >= 4) AS orders_left_join_filter_where;

-- Control-question notes:
-- 1) NULL = NULL is UNKNOWN because NULL means an unknown value, not a concrete value.
-- 2) A predicate on the right table in WHERE removes NULL-extended rows produced by LEFT JOIN.
-- 3) NOT EXISTS checks absence of matching rows directly and is not poisoned by an unrelated
--    NULL in the subquery, unlike NOT IN under SQL three-valued logic.
