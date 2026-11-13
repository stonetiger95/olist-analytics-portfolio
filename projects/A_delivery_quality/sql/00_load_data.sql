-- Run with psql from the directory containing the nine source CSVs.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL client_encoding = 'UTF8';

CREATE TABLE public.customers (
    customer_id text,
    customer_unique_id text,
    customer_zip_code_prefix text,
    customer_city text,
    customer_state text
);
\copy public.customers FROM 'olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true)

CREATE TABLE public.geolocation (
    geolocation_zip_code_prefix text,
    geolocation_lat numeric,
    geolocation_lng numeric,
    geolocation_city text,
    geolocation_state text
);
\copy public.geolocation FROM 'olist_geolocation_dataset.csv' WITH (FORMAT csv, HEADER true)

CREATE TABLE public.order_items (
    order_id text,
    order_item_id integer,
    product_id text,
    seller_id text,
    shipping_limit_date timestamp,
    price numeric,
    freight_value numeric
);
\copy public.order_items FROM 'olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true)

CREATE TABLE public.payments (
    order_id text,
    payment_sequential integer,
    payment_type text,
    payment_installments integer,
    payment_value numeric
);
\copy public.payments FROM 'olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true)

CREATE TABLE public.reviews (
    review_id text,
    order_id text,
    review_score integer,
    review_comment_title text,
    review_comment_message text,
    review_creation_date timestamp,
    review_answer_timestamp timestamp
);
\copy public.reviews FROM 'olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true)

CREATE TABLE public.orders (
    order_id text,
    customer_id text,
    order_status text,
    order_purchase_timestamp timestamp,
    order_approved_at timestamp,
    order_delivered_carrier_date timestamp,
    order_delivered_customer_date timestamp,
    order_estimated_delivery_date timestamp
);
\copy public.orders FROM 'olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true)

CREATE TABLE public.products (
    product_id text,
    product_category_name text,
    product_name_lenght integer,
    product_description_lenght integer,
    product_photos_qty integer,
    product_weight_g integer,
    product_length_cm integer,
    product_height_cm integer,
    product_width_cm integer
);
\copy public.products FROM 'olist_products_dataset.csv' WITH (FORMAT csv, HEADER true)

CREATE TABLE public.sellers (
    seller_id text,
    seller_zip_code_prefix text,
    seller_city text,
    seller_state text
);
\copy public.sellers FROM 'olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true)

CREATE TABLE public.product_category_name_translation (
    product_category_name text,
    product_category_name_english text
);
\copy public.product_category_name_translation FROM 'product_category_name_translation.csv' WITH (FORMAT csv, HEADER true)

COMMIT;
