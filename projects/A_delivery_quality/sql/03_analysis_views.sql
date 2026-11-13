/*
============================================================
Olist E-Commerce Analytics Portfolio

Project A - 분석용 뷰 구축
Database: PostgreSQL (olist)

[작업 내용]
- 주문·리뷰·지역·판매자·상품군 단위의 분석용 뷰를 생성한다.
- 뷰별 검증 쿼리로 집계 단위와 대상 주문 수를 확인한다.
============================================================
*/

-- 분석용 스키마 생성
CREATE SCHEMA IF NOT EXISTS analytics;

-- ==========================================================
-- TASK A-08. 주문 단위 배송 View 생성
-- ==========================================================

CREATE OR REPLACE VIEW analytics.v_order_delivery AS
SELECT o.order_id, c.customer_id,
        o.order_purchase_timestamp::date AS purchase_date,
        date_trunc('month', o.order_purchase_timestamp::date) AS purchase_month,
        c.customer_state,
        c.customer_city,
        (o.order_delivered_customer_date::date
        - o.order_estimated_delivery_date ::date) AS delay_days,
        CASE WHEN (o.order_delivered_customer_date::date
        - o.order_estimated_delivery_date ::date) > 0 THEN 1
            ELSE 0
        END AS is_delayed
FROM orders AS o
JOIN customers AS c
    ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
    AND o.order_delivered_customer_date IS NOT NULL
    AND o.order_estimated_delivery_date IS NOT NULL
;

-- 검증

SELECT
    COUNT(*) AS total_orders,
    COUNT(DISTINCT order_id) AS unique_orders,
    SUM(is_delayed) AS delayed_orders,
    ROUND(AVG(is_delayed) * 100, 2) AS delay_rate
FROM analytics.v_order_delivery;

-- ==========================================================
-- TASK A-09. 주문 단위 리뷰 분석 View 구축
-- ==========================================================
CREATE OR REPLACE VIEW analytics.v_order_review AS
WITH review_agg AS (
    SELECT order_id,
            COUNT(*) AS review_count,
            MAX(review_score) AS review_score
        FROM reviews
    GROUP BY order_id
        )
SELECT d.order_id, d.delay_days, d.is_delayed,
        COALESCE(r.review_count,0) AS review_count,
        CASE WHEN  r.review_count = 1 THEN 'Single Review'
            WHEN  r.review_count > 1 THEN 'Multiple Reviews'
            ELSE  'No Reviews' END AS review_status,
        CASE WHEN  r.review_count = 1 THEN r.review_score
            ELSE  NULL END AS review_score,
        CASE WHEN  r.review_count = 1 AND r.review_score <=2 THEN 1
            WHEN  r.review_count = 1 AND r.review_score > 2 THEN 0
            ELSE  NULL END AS is_low_rating
FROM analytics.v_order_delivery AS d
LEFT JOIN review_agg AS r
    ON d.order_id = r.order_id
;

-- View 검증

SELECT
    review_status,
    COUNT(*) AS total_orders,
    COUNT(review_score) AS valid_scores,
    COUNT(is_low_rating) AS valid_low_rating
FROM analytics.v_order_review
GROUP BY review_status
ORDER BY review_status;

-- ==========================================================
-- TASK A-10. 고객 지역별 배송 품질 KPI 구축
-- ==========================================================

CREATE OR REPLACE VIEW analytics.v_state_kpi AS
SELECT d.customer_state,
        COUNT(d.order_id) AS total_orders,
        SUM(d.is_delayed) AS delayed_orders,
        ROUND(AVG(d.is_delayed::numeric) * 100, 2) AS delay_rate_pct,
        COUNT(r.is_low_rating) AS reviewed_orders,
        SUM(r.is_low_rating) AS low_rating_count,
        ROUND(AVG(r.is_low_rating::numeric) * 100,2) AS low_rating_rate_pct
FROM analytics.v_order_delivery d
LEFT JOIN analytics.v_order_review r
    ON d.order_id = r.order_id
GROUP BY d.customer_state ;

-- View 검증
SELECT
    SUM(total_orders) AS total_orders,
    SUM(delayed_orders) AS delayed_orders,
    SUM(reviewed_orders) AS reviewed_orders,
    SUM(low_rating_count) AS low_rating_orders
FROM analytics.v_state_kpi;

SELECT *
FROM analytics.v_state_kpi
ORDER BY delay_rate_pct DESC;

SELECT
    COUNT(*) AS state_count,
    SUM(total_orders) AS total_orders,
    SUM(delayed_orders) AS delayed_orders,
    SUM(reviewed_orders) AS reviewed_orders,
    SUM(low_rating_count) AS low_rating_orders
FROM analytics.v_state_kpi;


-- ==========================================================
-- TASK A-11-1. 주문별 판매자 수 확인
-- ==========================================================
WITH seller_per_order AS (
    SELECT d.order_id,
            COUNT(DISTINCT oi.seller_id) AS seller_count
        FROM analytics.v_order_delivery AS d
        LEFT JOIN order_items AS oi
        ON d.order_id = oi.order_id
    GROUP BY d.order_id
)
SELECT COUNT(*) AS total_orders,
        COUNT(*) FILTER (WHERE seller_count = 0) AS no_seller_orders,
        COUNT(*) FILTER (WHERE seller_count = 1) AS single_seller_orders,
        COUNT(*) FILTER (WHERE seller_count > 1) AS multi_seller_orders,
        MAX(seller_count) AS max_sellers_per_order
FROM seller_per_order;

-- ==========================================================
-- TASK A-11-2. 주문 × 판매자 단위 View 구축
-- ==========================================================

CREATE OR REPLACE VIEW analytics.v_seller_order AS
WITH order_seller AS (
    SELECT DISTINCT order_id, seller_id
        FROM order_items
        )
SELECT d.order_id , o.seller_id , d.is_delayed , d.delay_days,
        r.is_low_rating, d.customer_state, s.seller_state
FROM analytics.v_order_delivery d
JOIN order_seller o
    ON d.order_id = o.order_id
LEFT JOIN analytics.v_order_review r
    ON o.order_id = r.order_id
JOIN public.sellers s
    ON s.seller_id = o.seller_id;

-- View 검증

SELECT
    COUNT(*) AS total_seller_orders,
    COUNT(DISTINCT order_id) AS unique_orders,
    COUNT(DISTINCT (order_id, seller_id)) AS unique_pairs
FROM analytics.v_seller_order;


-- ==========================================================
-- TASK A-11-3. 판매자별 배송 품질 KPI 구축
-- ==========================================================

CREATE OR REPLACE VIEW analytics.v_seller_kpi AS
WITH seller_order_count AS (
    SELECT *, COUNT(*) OVER (PARTITION BY order_id) AS seller_count
        FROM analytics.v_seller_order
)
SELECT seller_id , seller_state,
        COUNT(order_id) AS total_orders,
        SUM(is_delayed) AS delayed_orders,
        ROUND(AVG(is_delayed::numeric)*100, 2) AS delay_rate_pct,
        COUNT(is_low_rating) AS reviewed_orders,
        SUM(is_low_rating) AS low_rating_count,
        ROUND(AVG(is_low_rating::numeric) * 100,2) AS low_rating_rate_pct
FROM seller_order_count
WHERE seller_count = 1
GROUP BY seller_id, seller_state;
--

SELECT
    COUNT(*) AS seller_count,
    SUM(total_orders) AS total_orders,
    SUM(delayed_orders) AS delayed_orders,
    SUM(reviewed_orders) AS reviewed_orders,
    SUM(low_rating_count) AS low_rating_orders
FROM analytics.v_seller_kpi;

-- ==========================================================
-- TASK A-11-4. 판매자 수에 따른 주문 특성 검증
-- ==========================================================
-- [추가 탐색 1] 단일·다중 판매자 주문의 배송 지연 여부별 저평점 비율 비교
-- 목적: 다중 판매자 주문의 높은 저평점 비율이 배송 지연과 관련 있는지 확인
WITH order_level AS (
    SELECT order_id,
            COUNT(*) AS seller_count,
            MAX(is_delayed) AS is_delayed,
            MAX(is_low_rating) AS is_low_rating
    FROM analytics.v_seller_order
    GROUP BY order_id
        )
SELECT CASE WHEN  seller_count = 1 THEN 'Single Seller'
            ELSE  'Multiple Sellers' END AS seller_type,
        COUNT(*) AS total_orders,
        SUM(is_delayed) AS delayed_orders,
        COUNT(is_low_rating) AS reviewed_orders,
        SUM(is_low_rating) AS low_rating_orders,
        ROUND(AVG(is_delayed::numeric) * 100, 2) AS delay_rate_pct,
        ROUND(AVG(is_low_rating::numeric) * 100, 2) AS low_rating_rate_pct
FROM order_level
GROUP BY seller_type;

-- 결과:
-- 정시·조기 배송에서도 다중 판매자 저평점 비율 47.17%, 단일 판매자 8.72%.
-- 배송 지연 여부만으로 두 집단의 저평점 비율 차이를 설명하기 어려움.

WITH order_level AS (
    SELECT
        order_id,
        COUNT(*) AS seller_count,
        MAX(is_delayed) AS is_delayed,
        MAX(is_low_rating) AS is_low_rating
    FROM analytics.v_seller_order
    GROUP BY order_id
)
SELECT
    CASE
        WHEN seller_count = 1 THEN 'Single Seller'
        ELSE 'Multiple Sellers'
    END AS seller_type,
    is_delayed,
    COUNT(*) AS total_orders,
    COUNT(is_low_rating) AS reviewed_orders,
    ROUND(
        AVG(is_low_rating::numeric) * 100, 2
    ) AS low_rating_rate_pct
FROM order_level
GROUP BY
    seller_type,
    is_delayed
ORDER BY
    seller_type,
    is_delayed;


-- [추가 탐색 2] 정시·조기 배송 주문의 실제 배송 소요시간 비교
-- 목적: 다중 판매자 주문의 낮은 평점이 긴 배송 소요시간과 관련 있는지 확인
WITH seller_counts AS (
    SELECT
        order_id,
        COUNT(*) AS seller_count
    FROM analytics.v_seller_order
    GROUP BY order_id
)
SELECT
    CASE
        WHEN sc.seller_count = 1 THEN 'Single Seller'
        ELSE 'Multiple Sellers'
    END AS seller_type,
    COUNT(*) AS total_orders,
    ROUND(AVG(
        o.order_delivered_customer_date::date
        - o.order_purchase_timestamp::date
    ), 2) AS avg_delivery_days,
    PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY
            o.order_delivered_customer_date::date
            - o.order_purchase_timestamp::date
    ) AS median_delivery_days,
    ROUND(AVG(
        o.order_estimated_delivery_date::date
        - o.order_purchase_timestamp::date
    ), 2) AS avg_expected_days
FROM seller_counts sc
JOIN analytics.v_order_delivery d
    ON sc.order_id = d.order_id
JOIN orders o
    ON sc.order_id = o.order_id
WHERE d.is_delayed = 0
GROUP BY seller_type;


-- 결과:
-- 평균 실제 배송 소요시간: 다중 8.87일, 단일 10.97일.
-- 다중 판매자 주문이 오히려 더 빨리 배송되어 초기 가설과 반대되는 결과.

-- ==========================================================
-- TASK A-12-1. 주문별 상품군 개수 및 결측 검증
-- ==========================================================

WITH category_per_order AS (
    SELECT
        d.order_id,
        COUNT(DISTINCT p.product_category_name)
            AS category_count,
        COUNT(*) FILTER (
            WHERE oi.product_id IS NOT NULL
                AND p.product_category_name IS NULL
        ) AS uncategorized_items,
        COUNT(*) FILTER (
            WHERE oi.product_id IS NOT NULL
                AND p.product_id IS NULL
        ) AS unmatched_products
    FROM analytics.v_order_delivery d
    LEFT JOIN order_items oi
        ON d.order_id = oi.order_id
    LEFT JOIN products p
        ON oi.product_id = p.product_id
    GROUP BY d.order_id
)
SELECT
    COUNT(*) AS total_orders,
    COUNT(*) FILTER (
        WHERE category_count = 0
    ) AS no_category_orders,
    COUNT(*) FILTER (
        WHERE category_count = 1
    ) AS single_category_orders,
    COUNT(*) FILTER (
        WHERE category_count > 1
    ) AS multi_category_orders,
    MAX(category_count) AS max_categories_per_order,
    COUNT(*) FILTER (
        WHERE uncategorized_items > 0
    ) AS orders_with_uncategorized_items,
    SUM(unmatched_products) AS unmatched_product_items
FROM category_per_order;

-- ==========================================================
-- TASK A-12-2. 상품군 결측 유형 확인
-- ==========================================================

WITH category_per_order AS (
    SELECT
        d.order_id,
        COUNT(DISTINCT p.product_category_name)
            AS category_count,
        BOOL_OR(
            oi.product_id IS NOT NULL
            AND p.product_category_name IS NULL
        ) AS has_missing_category
    FROM analytics.v_order_delivery d
    LEFT JOIN order_items oi
        ON d.order_id = oi.order_id
    LEFT JOIN products p
        ON oi.product_id = p.product_id
    GROUP BY d.order_id
)
SELECT
    CASE
        WHEN category_count = 0 THEN 'No Category'
        WHEN category_count = 1 THEN 'Single Category'
        ELSE 'Multiple Categories'
    END AS category_type,
    has_missing_category,
    COUNT(*) AS total_orders
FROM category_per_order
GROUP BY category_type, has_missing_category
ORDER BY category_type, has_missing_category;

-- ==========================================================
-- TASK A-12-3. 주문 × 상품군 View 구축
-- ==========================================================

CREATE OR REPLACE VIEW analytics.v_category_order AS
WITH order_category AS (
    SELECT DISTINCT oi.order_id, p.product_category_name
        FROM order_items oi
        JOIN products p
        ON oi.product_id = p.product_id
    WHERE p.product_category_name IS NOT NULL
),
category_quality AS (
    SELECT oi.order_id,
            COUNT(DISTINCT p.product_category_name) AS category_count,
            BOOL_OR(p.product_category_name IS NULL) AS has_missing_category
        FROM order_items oi
        LEFT JOIN products p
        ON oi.product_id = p.product_id
    GROUP BY oi.order_id
)
SELECT c.order_id, c.product_category_name,
        d.delay_days, d.is_delayed,
        r.is_low_rating, q.category_count, q.has_missing_category
FROM order_category c
JOIN analytics.v_order_delivery d
    ON c.order_id = d.order_id
JOIN analytics.v_order_review r
    ON r.order_id = c.order_id
LEFT JOIN category_quality q
    ON c.order_id = q.order_id  ;

-- View 검증

SELECT
    COUNT(*) AS total_category_orders,
    COUNT(DISTINCT order_id) AS unique_orders,
    COUNT(DISTINCT (order_id, product_category_name)) AS unique_pairs,
    COUNT(DISTINCT order_id) FILTER (
        WHERE category_count = 1
        AND has_missing_category = FALSE
    ) AS valid_single_category_orders
FROM analytics.v_category_order;

-- ==========================================================
-- TASK A-12-4. 상품군별 KPI View 구축
-- ==========================================================

CREATE OR REPLACE VIEW analytics.v_category_kpi AS
SELECT product_category_name,
        COUNT(*) AS total_orders,
        SUM(is_delayed) AS delayed_orders, --count(*) filter(where is_delayed = 1)
        COUNT(is_low_rating) AS reviewed_orders,
        SUM(is_low_rating) AS low_rating_orders,
        ROUND(AVG(is_delayed::numeric) * 100, 2) AS delay_rate_pct,
        ROUND(AVG(is_low_rating::numeric) * 100, 2) AS low_rating_rate_pct
FROM analytics.v_category_order
WHERE category_count = 1
    AND has_missing_category = false
GROUP BY product_category_name;

-- View 검증
SELECT
    COUNT(*) AS category_count,
    SUM(total_orders) AS total_orders,
    SUM(delayed_orders) AS delayed_orders,
    SUM(reviewed_orders) AS reviewed_orders,
    SUM(low_rating_orders) AS low_rating_orders
FROM analytics.v_category_kpi;

SELECT
    COUNT(*) AS total_orders,
    SUM(is_delayed) AS delayed_orders,
    COUNT(is_low_rating) AS reviewed_orders,
    SUM(is_low_rating) AS low_rating_orders
FROM analytics.v_category_order
WHERE category_count = 1
AND has_missing_category = FALSE;

SELECT *
FROM analytics.v_category_kpi
ORDER BY delay_rate_pct DESC
LIMIT 10;
