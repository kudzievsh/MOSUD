-- Контрольные проверки практической работы №1

-- Количество строк.
SELECT 'customers' AS table_name, count(*) AS row_count FROM olist.customers
UNION ALL SELECT 'geolocation', count(*) FROM olist.geolocation
UNION ALL SELECT 'orders', count(*) FROM olist.orders
UNION ALL SELECT 'order_items', count(*) FROM olist.order_items
UNION ALL SELECT 'order_payments', count(*) FROM olist.order_payments
UNION ALL SELECT 'order_reviews', count(*) FROM olist.order_reviews
UNION ALL SELECT 'products', count(*) FROM olist.products
UNION ALL SELECT 'sellers', count(*) FROM olist.sellers
UNION ALL SELECT 'product_category_name_translation', count(*) FROM olist.product_category_name_translation
ORDER BY 1;

-- NULL в ключевых полях.
SELECT 'customers.customer_id' AS key_field, count(*) AS null_count FROM olist.customers WHERE customer_id IS NULL
UNION ALL SELECT 'orders.order_id', count(*) FROM olist.orders WHERE order_id IS NULL
UNION ALL SELECT 'orders.customer_id', count(*) FROM olist.orders WHERE customer_id IS NULL
UNION ALL SELECT 'order_items.order_id', count(*) FROM olist.order_items WHERE order_id IS NULL
UNION ALL SELECT 'order_items.product_id', count(*) FROM olist.order_items WHERE product_id IS NULL
UNION ALL SELECT 'order_items.seller_id', count(*) FROM olist.order_items WHERE seller_id IS NULL
UNION ALL SELECT 'order_payments.order_id', count(*) FROM olist.order_payments WHERE order_id IS NULL
UNION ALL SELECT 'order_reviews.review_id', count(*) FROM olist.order_reviews WHERE review_id IS NULL
UNION ALL SELECT 'order_reviews.order_id', count(*) FROM olist.order_reviews WHERE order_id IS NULL
UNION ALL SELECT 'products.product_id', count(*) FROM olist.products WHERE product_id IS NULL
UNION ALL SELECT 'sellers.seller_id', count(*) FROM olist.sellers WHERE seller_id IS NULL
UNION ALL SELECT 'translation.product_category_name', count(*) FROM olist.product_category_name_translation WHERE product_category_name IS NULL
ORDER BY 1;

-- Осиротевшие внешние ссылки.
SELECT 'orders -> customers' AS relation_name, count(*) AS orphan_count
FROM olist.orders o LEFT JOIN olist.customers c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL
UNION ALL
SELECT 'order_items -> orders', count(*)
FROM olist.order_items oi LEFT JOIN olist.orders o ON o.order_id = oi.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'order_items -> products', count(*)
FROM olist.order_items oi LEFT JOIN olist.products p ON p.product_id = oi.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT 'order_items -> sellers', count(*)
FROM olist.order_items oi LEFT JOIN olist.sellers s ON s.seller_id = oi.seller_id
WHERE s.seller_id IS NULL
UNION ALL
SELECT 'order_payments -> orders', count(*)
FROM olist.order_payments op LEFT JOIN olist.orders o ON o.order_id = op.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'order_reviews -> orders', count(*)
FROM olist.order_reviews r LEFT JOIN olist.orders o ON o.order_id = r.order_id
WHERE o.order_id IS NULL
ORDER BY 1;

-- Дубликаты составных ключей.
SELECT order_id, order_item_id, count(*) AS duplicate_count
FROM olist.order_items
GROUP BY order_id, order_item_id
HAVING count(*) > 1
ORDER BY duplicate_count DESC;

SELECT order_id, payment_sequential, count(*) AS duplicate_count
FROM olist.order_payments
GROUP BY order_id, payment_sequential
HAVING count(*) > 1
ORDER BY duplicate_count DESC;

SELECT review_id, order_id, count(*) AS duplicate_count
FROM olist.order_reviews
GROUP BY review_id, order_id
HAVING count(*) > 1
ORDER BY duplicate_count DESC;

-- ANALYZE.
ANALYZE olist.customers;
ANALYZE olist.geolocation;
ANALYZE olist.orders;
ANALYZE olist.order_items;
ANALYZE olist.order_payments;
ANALYZE olist.order_reviews;
ANALYZE olist.products;
ANALYZE olist.sellers;
ANALYZE olist.product_category_name_translation;

SELECT version() AS postgresql_version, current_database() AS database_name, now() AS checked_at;
