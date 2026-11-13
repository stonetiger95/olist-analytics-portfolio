-- 분석용 스키마 생성
CREATE SCHEMA IF NOT EXISTS analytics;

-- TASK D03-01. 주문 단위 배송 View 생성

CREATE OR REPLACE VIEW analytics.v_order_delivery AS
select  o.order_id, c.customer_id,
		o.order_purchase_timestamp::date as purchase_date, 
		date_trunc('month', o.order_purchase_timestamp::date) as purchase_month,
		c.customer_state,
		c.customer_city,
		(o.order_delivered_customer_date::date 
		- o.order_estimated_delivery_date ::date) as delay_days,
		case when (o.order_delivered_customer_date::date 
		- o.order_estimated_delivery_date ::date) > 0 then 1 
			 else 0 
		end as is_delayed
  from  orders AS o
  join  customers AS c
    on  o.customer_id = c.customer_id
 where  o.order_status = 'delivered'
   and  o.order_delivered_customer_date is not null 
   and  o.order_estimated_delivery_date is not null
;

-- 검증 

SELECT
    COUNT(*) AS total_orders,
    COUNT(DISTINCT order_id) AS unique_orders,
    SUM(is_delayed) AS delayed_orders,
    ROUND(AVG(is_delayed) * 100, 2) AS delay_rate
FROM analytics.v_order_delivery;

-- TASK D03-02. 주문 단위 리뷰 분석 View 구축
CREATE OR REPLACE VIEW analytics.v_order_review as
with review_agg as (
	select  order_id, 
			count(*) as review_count,
			max(review_score) as review_score
	  from  reviews
	 group
	 	by  order_id
	 	)
select  d.order_id, d.delay_days, d.is_delayed,
		coalesce(r.review_count,0) as review_count,
		case when  r.review_count = 1 then 'Single Review'
			 when  r.review_count > 1 then 'Multiple Reviews'
			 else  'No Reviews' end as review_status,
	    case when  r.review_count = 1 then r.review_score
	    	 else  null end as review_score,
	    case when  r.review_count = 1 and r.review_score <=2 then 1
	    	 when  r.review_count = 1 and r.review_score > 2 then 0 
	    	 else  null end as is_low_rating
  from  analytics.v_order_delivery as d
  left
  join  review_agg as r 
    on  d.order_id = r.order_id
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

-- TASK D03-03. 고객 지역별 배송 품질 KPI 구축

CREATE OR REPLACE VIEW analytics.v_state_kpi as
select  d.customer_state,
		count(d.order_id) as total_orders,
		sum(d.is_delayed) as delayed_orders, 
		ROUND(AVG(d.is_delayed::numeric) * 100, 2) AS delay_rate_pct,
		COUNT(r.is_low_rating) AS reviewed_orders,
		sum(r.is_low_rating) as low_rating_count,
		ROUND(AVG(r.is_low_rating::numeric) * 100,2) AS low_rating_rate_pct
  from  analytics.v_order_delivery d
  left
  join  analytics.v_order_review r 
    on  d.order_id = r.order_id
 group
 	by  d.customer_state ;

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


-- 주문별로 셀러가 몇명인지 확인
WITH seller_per_order AS (
    select  d.order_id,
      		COUNT(DISTINCT oi.seller_id) AS seller_count
      from  analytics.v_order_delivery AS d
      left
      join  order_items AS oi
        on  d.order_id = oi.order_id
     group
     	by  d.order_id
)
select  COUNT(*) AS total_orders,
    	COUNT(*) FILTER (WHERE seller_count = 0) AS no_seller_orders,
    	COUNT(*) FILTER (WHERE seller_count = 1) AS single_seller_orders,
    	COUNT(*) FILTER (WHERE seller_count > 1) AS multi_seller_orders,
    	MAX(seller_count) AS max_sellers_per_order
  from  seller_per_order;

-- TASK D03-04-2. 주문 × 판매자 단위 View 구축

CREATE OR REPLACE VIEW analytics.v_seller_order as
with order_seller as (
	select  distinct order_id, seller_id
	  from  order_items
	  )
select  d.order_id , o.seller_id , d.is_delayed , d.delay_days, 
		r.is_low_rating, d.customer_state, s.seller_state  
  from  analytics.v_order_delivery d
  join  order_seller o
    on  d.order_id = o.order_id
  left
  join  analytics.v_order_review r
    on  o.order_id = r.order_id
  join  public.sellers s 
    on  s.seller_id = o.seller_id;

-- View 검증

SELECT
    COUNT(*) AS total_seller_orders,
    COUNT(DISTINCT order_id) AS unique_orders,
    COUNT(DISTINCT (order_id, seller_id)) AS unique_pairs
FROM analytics.v_seller_order;


-- TASK D03-04-3. 판매자별 배송 품질 KPI 구축

CREATE OR REPLACE VIEW analytics.v_seller_kpi as
with seller_order_count as (
	select  *, count(*) over (partition by order_id) as seller_count
	  from  analytics.v_seller_order
)
select  seller_id , seller_state,
		count(order_id) as total_orders,
		sum(is_delayed) as delayed_orders,
		round(avg(is_delayed::numeric)*100, 2) as delay_rate_pct,
		COUNT(is_low_rating) AS reviewed_orders,
		sum(is_low_rating) as low_rating_count,
		ROUND(AVG(is_low_rating::numeric) * 100,2) AS low_rating_rate_pct 
  from  seller_order_count
 where  seller_count = 1
 group
    by  seller_id, seller_state;
--

SELECT
    COUNT(*) AS seller_count,
    SUM(total_orders) AS total_orders,
    SUM(delayed_orders) AS delayed_orders,
    SUM(reviewed_orders) AS reviewed_orders,
    SUM(low_rating_count) AS low_rating_orders
FROM analytics.v_seller_kpi;

-- TASK D03-04-4. 판매자 수에 따른 주문 특성 검증
-- [추가 탐색 1] 단일·다중 판매자 주문의 배송 지연 여부별 저평점 비율 비교
-- 목적: 다중 판매자 주문의 높은 저평점 비율이 배송 지연과 관련 있는지 확인
WITH order_level AS (
    select  order_id,
    		COUNT(*) AS seller_count,
    		MAX(is_delayed) AS is_delayed,
    		MAX(is_low_rating) AS is_low_rating
     from  analytics.v_seller_order
    group 
       by  order_id
       )
select  case when  seller_count = 1 THEN 'Single Seller'
        	 else  'Multiple Sellers' END AS seller_type,
    	COUNT(*) AS total_orders,
    	SUM(is_delayed) AS delayed_orders,
    	COUNT(is_low_rating) AS reviewed_orders,
    	SUM(is_low_rating) AS low_rating_orders,
    	ROUND(AVG(is_delayed::numeric) * 100, 2) AS delay_rate_pct,
    	ROUND(AVG(is_low_rating::numeric) * 100, 2) AS low_rating_rate_pct
  from  order_level
 group
	by  seller_type;

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

-- TASK D03-05-1. 주문별 상품군 개수 및 결측 검증

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

-- TASK D03-05-2. 상품군 결측 유형 확인

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

-- TASK D03-05-3. 주문 × 상품군 View 구축

CREATE OR REPLACE VIEW analytics.v_category_order as
WITH order_category AS (
    select  distinct oi.order_id, p.product_category_name
      from  order_items oi
      join  products p
        on  oi.product_id = p.product_id
     where  p.product_category_name IS NOT NULL
),
category_quality AS (
    select  oi.order_id,
            COUNT(DISTINCT p.product_category_name) AS category_count,
        	BOOL_OR(p.product_category_name IS NULL) AS has_missing_category
      from  order_items oi
      left
      join  products p
        on  oi.product_id = p.product_id
     group
     	by  oi.order_id
)
select  c.order_id, c.product_category_name, 
		d.delay_days, d.is_delayed,
		r.is_low_rating, q.category_count, q.has_missing_category
  from  order_category c
  join  analytics.v_order_delivery d
    on  c.order_id = d.order_id 
  join  analytics.v_order_review r
    on  r.order_id = c.order_id
  left  
  join  category_quality q
	ON  c.order_id = q.order_id	;
  
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

-- TASK D03-05-4. 상품군별 KPI View 구축

CREATE OR REPLACE VIEW analytics.v_category_kpi AS
select  product_category_name,
		COUNT(*) AS total_orders,
    	SUM(is_delayed) AS delayed_orders, --count(*) filter(where is_delayed = 1)  
    	COUNT(is_low_rating) AS reviewed_orders,
    	SUM(is_low_rating) AS low_rating_orders,
    	ROUND(AVG(is_delayed::numeric) * 100, 2) AS delay_rate_pct,
    	ROUND(AVG(is_low_rating::numeric) * 100, 2) AS low_rating_rate_pct
  from  analytics.v_category_order
 where  category_count = 1 
   and  has_missing_category = false 
 group
 	by  product_category_name;

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


