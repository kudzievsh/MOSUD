CREATE SCHEMA IF NOT EXISTS olist;
CREATE SCHEMA IF NOT EXISTS lab;

DROP TABLE IF EXISTS olist.order_reviews CASCADE;
DROP TABLE IF EXISTS olist.order_payments CASCADE;
DROP TABLE IF EXISTS olist.order_items CASCADE;
DROP TABLE IF EXISTS olist.orders CASCADE;
DROP TABLE IF EXISTS olist.products CASCADE;
DROP TABLE IF EXISTS olist.sellers CASCADE;
DROP TABLE IF EXISTS olist.customers CASCADE;
DROP TABLE IF EXISTS olist.geolocation CASCADE;
DROP TABLE IF EXISTS olist.product_category_name_translation CASCADE;

CREATE TABLE olist.customers (
    customer_id text NOT NULL,
    customer_unique_id text,
    customer_zip_code_prefix integer,
    customer_city text,
    customer_state text
);

CREATE TABLE olist.geolocation (
    geolocation_zip_code_prefix integer,
    geolocation_lat numeric(12,8),
    geolocation_lng numeric(12,8),
    geolocation_city text,
    geolocation_state text
);

CREATE TABLE olist.orders (
    order_id text NOT NULL,
    customer_id text NOT NULL,
    order_status text,
    order_purchase_timestamp timestamp,
    order_approved_at timestamp,
    order_delivered_carrier_date timestamp,
    order_delivered_customer_date timestamp,
    order_estimated_delivery_date timestamp
);

CREATE TABLE olist.order_items (
    order_id text NOT NULL,
    order_item_id integer NOT NULL,
    product_id text NOT NULL,
    seller_id text NOT NULL,
    shipping_limit_date timestamp,
    price numeric(10,2),
    freight_value numeric(10,2)
);

CREATE TABLE olist.order_payments (
    order_id text NOT NULL,
    payment_sequential integer NOT NULL,
    payment_type text,
    payment_installments integer,
    payment_value numeric(10,2)
);

CREATE TABLE olist.order_reviews (
    review_id text NOT NULL,
    order_id text NOT NULL,
    review_score smallint,
    review_comment_title text,
    review_comment_message text,
    review_creation_date timestamp,
    review_answer_timestamp timestamp
);

CREATE TABLE olist.products (
    product_id text NOT NULL,
    product_category_name text,
    product_name_lenght integer,
    product_description_lenght integer,
    product_photos_qty integer,
    product_weight_g integer,
    product_length_cm integer,
    product_height_cm integer,
    product_width_cm integer
);

CREATE TABLE olist.sellers (
    seller_id text NOT NULL,
    seller_zip_code_prefix integer,
    seller_city text,
    seller_state text
);

CREATE TABLE olist.product_category_name_translation (
    product_category_name text NOT NULL,
    product_category_name_english text
);

-- Массовая загрузка CSV.
\copy olist.customers FROM '/data/olist/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

\copy olist.geolocation FROM '/data/olist/olist_geolocation_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

\copy olist.orders FROM '/data/olist/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

\copy olist.order_items FROM '/data/olist/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

\copy olist.order_payments FROM '/data/olist/olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

\copy olist.order_reviews FROM '/data/olist/olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

\copy olist.products FROM '/data/olist/olist_products_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

\copy olist.sellers FROM '/data/olist/olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

\copy olist.product_category_name_translation FROM '/data/olist/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

-- Первичные ключи.
ALTER TABLE olist.customers
    ADD CONSTRAINT pk_customers PRIMARY KEY (customer_id);

ALTER TABLE olist.orders
    ADD CONSTRAINT pk_orders PRIMARY KEY (order_id);

ALTER TABLE olist.products
    ADD CONSTRAINT pk_products PRIMARY KEY (product_id);

ALTER TABLE olist.sellers
    ADD CONSTRAINT pk_sellers PRIMARY KEY (seller_id);

ALTER TABLE olist.product_category_name_translation
    ADD CONSTRAINT pk_category_translation
    PRIMARY KEY (product_category_name);

ALTER TABLE olist.order_items
    ADD CONSTRAINT pk_order_items
    PRIMARY KEY (order_id, order_item_id);

ALTER TABLE olist.order_payments
    ADD CONSTRAINT pk_order_payments
    PRIMARY KEY (order_id, payment_sequential);

ALTER TABLE olist.order_reviews
    ADD CONSTRAINT pk_order_reviews
    PRIMARY KEY (review_id, order_id);

-- Внешние ключи.
ALTER TABLE olist.orders
    ADD CONSTRAINT fk_orders_customer
    FOREIGN KEY (customer_id)
    REFERENCES olist.customers(customer_id);

ALTER TABLE olist.order_items
    ADD CONSTRAINT fk_items_order
    FOREIGN KEY (order_id)
    REFERENCES olist.orders(order_id);

ALTER TABLE olist.order_items
    ADD CONSTRAINT fk_items_product
    FOREIGN KEY (product_id)
    REFERENCES olist.products(product_id);

ALTER TABLE olist.order_items
    ADD CONSTRAINT fk_items_seller
    FOREIGN KEY (seller_id)
    REFERENCES olist.sellers(seller_id);

ALTER TABLE olist.order_payments
    ADD CONSTRAINT fk_payments_order
    FOREIGN KEY (order_id)
    REFERENCES olist.orders(order_id);

ALTER TABLE olist.order_reviews
    ADD CONSTRAINT fk_reviews_order
    FOREIGN KEY (order_id)
    REFERENCES olist.orders(order_id);

-- Статистика для планировщика.
ANALYZE olist.customers;
ANALYZE olist.geolocation;
ANALYZE olist.orders;
ANALYZE olist.order_items;
ANALYZE olist.order_payments;
ANALYZE olist.order_reviews;
ANALYZE olist.products;
ANALYZE olist.sellers;
ANALYZE olist.product_category_name_translation;
