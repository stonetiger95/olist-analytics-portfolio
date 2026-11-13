/*
============================================================
Olist E-Commerce Analytics Portfolio

Project A - 배송 품질 운영 분석
Database: PostgreSQL (olist)

[작업 내용]
- 분석용 뷰로 지역·판매자·상품군별 배송 지연과 월별 추이를 살펴본다.
- 초과 지연 건수는 기준 지연율 대비 관측된 차이를 뜻한다.
============================================================
*/

-- ==========================================================
-- TASK A-13-1. 지역별 배송 문제 진단
-- ==========================================================

SELECT customer_state,
        total_orders,
        delayed_orders,
        delay_rate_pct,
        low_rating_rate_pct
FROM analytics.v_state_kpi
ORDER BY delayed_orders DESC
LIMIT  10;

-- ==========================================================
-- TASK A-13-2. 지역별 초과 지연 건수 계산
-- ==========================================================
WITH benchmark AS (
    SELECT SUM(delayed_orders)::numeric/SUM(total_orders) AS overall_delay_rate
        FROM analytics.v_state_kpi
)
SELECT s.*,
        ROUND(s.delayed_orders-(s.total_orders * b.overall_delay_rate),1) AS excess_delayed_orders
FROM analytics.v_state_kpi s
CROSS JOIN benchmark b
ORDER BY excess_delayed_orders DESC;

/*
지역 분석 결론
전체 평균 대비 초과 지연 건수를 기준으로 RJ, BA, CE가 주요 개선 검토 지역으로 나타났다. 특히 RJ는 초과 지연 규모가 가장 크다.
반면 AL 등 상대적으로 주문량이 적지만 지연율이 높은 지역은 별도 모니터링 대상으로 관리할 필요가 있다.
선정 기준은 초기 운영 가정이며 실제 개선 효과를 의미하지 않는다.
*/

-- ==========================================================
-- TASK A-14-1. 판매자별 주문량 분포 확인
-- ==========================================================

SELECT COUNT(*) AS seller_count,
        MIN(total_orders) AS min_orders,
        -- 중앙값
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_orders) AS p50,
        -- 75백분위수
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY total_orders) AS p75,
        -- 90백분위수
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY total_orders) AS p90,
        MAX(total_orders) AS max_orders,
        COUNT(*) FILTER (WHERE total_orders < 10) AS sellers_under_10,
        COUNT(*) FILTER (WHERE total_orders >= 30) AS sellers_30_plus,
        COUNT(*) FILTER (WHERE total_orders >= 100) AS sellers_100_plus
FROM analytics.v_seller_kpi;

-- ==========================================================
-- TASK A-14-2. 최소 주문 수 기준별 주문 커버리지
-- ==========================================================
WITH order_coverage AS (
    SELECT SUM(total_orders) AS all_orders,
            SUM(total_orders) FILTER(WHERE total_orders >= 30) AS orders_30_plus,
            SUM(total_orders) FILTER(WHERE total_orders >= 100) AS orders_100_plus
        FROM analytics.v_seller_kpi
        )
SELECT all_orders, orders_30_plus, orders_100_plus,
        ROUND(orders_30_plus::numeric / all_orders *100, 2) AS orders_30_plus_coverage,
        ROUND(orders_100_plus::numeric / all_orders *100, 2) AS orders_100_plus_coverage
FROM order_coverage;

-- ==========================================================
-- TASK A-14-3. 판매자별 초과 지연 건수 계산
-- ==========================================================

WITH benchmark AS (
    SELECT SUM(delayed_orders)::numeric/SUM(total_orders) AS overall_delay_rate
        FROM analytics.v_seller_kpi
)
SELECT s.*,
        ROUND(s.delayed_orders-(s.total_orders * b.overall_delay_rate),1) AS excess_delayed_orders
FROM analytics.v_seller_kpi s
CROSS JOIN benchmark b
WHERE s.total_orders >= 30
    AND s.delayed_orders::numeric / s.total_orders > b.overall_delay_rate
ORDER BY excess_delayed_orders DESC
LIMIT  10;

-- ==========================================================
-- TASK A-14-4. 판매자 소재 지역 분포 확인
-- ==========================================================

SELECT COUNT(*) AS total_sellers,
        COUNT(*) FILTER(WHERE seller_state = 'SP') AS sp_seller,
        ROUND(
            COUNT(*) FILTER(WHERE seller_state = 'SP')::numeric /
            COUNT(*) *100, 2
        ) AS sp_seller_pct,
        SUM(total_orders) AS total_orders,
        ROUND(
            SUM(total_orders) FILTER (WHERE seller_state = 'SP')::numeric /
            SUM(total_orders)*100, 2
        ) AS sp_order_pct
FROM analytics.v_seller_kpi
WHERE total_orders >= 30;

-- ==========================================================
-- TASK A-14-5. SP 판매자의 배송 목적지별 분석
-- ==========================================================

WITH sellers_in_order AS (
    SELECT *,
            COUNT(*) OVER (PARTITION BY order_id) AS seller_count
        FROM analytics.v_seller_order
)
SELECT sio.customer_state ,
        COUNT(*) AS total_orders,
        SUM(sio.is_delayed) AS delayed_orders,
        ROUND(AVG(sio.is_delayed::numeric)*100, 2) AS delay_rate_pct
FROM analytics.v_seller_kpi s
JOIN sellers_in_order sio
    ON s.seller_id  = sio.seller_id
WHERE s.seller_state = 'SP'
    AND sio.seller_count = 1
    AND s.total_orders >= 30
GROUP BY customer_state
ORDER BY total_orders DESC;

/*
- 판매자별 배송 품질 분석 결과

주문 30건 이상인 판매자 615명을 대상으로 배송 품질을 비교했으며, 이들이 전체 단일 판매자 주문의 83.17%를 차지함을 확인하였다.
초과 지연 건수 상위 10개 판매자 중 8개는 SP 소재였으나, SP 판매자가 분석 대상 주문의 73.04%를 담당한다는 점에서 이를 SP 판매자의 품질 문제로 단정하기는 어렵다.
SP 소재 판매자의 배송 목적지를 추가 분석한 결과, SP 목적지의 지연율은 4.48%인 반면 RJ 목적지는 14.29%로 나타났다.
이는 판매자 소재지뿐 아니라 배송 목적지와의 조합을 고려한 운영 점검이 필요함을 시사한다.
다만 배송 지연의 구체적인 원인은 확인되지 않았으므로 해당 결과는 개선 후보를 선정하기 위한 탐색적 분석으로 해석한다.

*/

-- ==========================================================
-- TASK A-15. 상품군별 개선 우선순위
-- ==========================================================
WITH benchmark AS (
    SELECT
        SUM(delayed_orders)::numeric
        / SUM(total_orders) AS overall_delay_rate
    FROM analytics.v_category_kpi
)
SELECT
    c.product_category_name,
    c.total_orders,
    c.delayed_orders,
    c.delay_rate_pct,
    c.low_rating_rate_pct,
    ROUND(
        c.delayed_orders
        - c.total_orders * b.overall_delay_rate,
        1
    ) AS excess_delayed_orders
FROM analytics.v_category_kpi c
CROSS JOIN benchmark b
WHERE c.total_orders >= 100
AND c.delayed_orders::numeric / c.total_orders > b.overall_delay_rate
ORDER BY excess_delayed_orders DESC;

/*

상품군별 초과 지연 건수를 분석한 결과, cama_mesa_banho, beleza_saude, bebes가 주요 개선 검토 후보로 나타났다.
이들 상품군은 전체 평균보다 지연율이 높으면서 실제 지연 주문 규모도 상대적으로 컸다.
다만 분석 대상은 단일 상품군으로 분류 가능한 주문에 한정되며, 초과 지연 건수는 실제 개선 가능 건수를 의미하지 않는다.

*/

-- ==========================================================
-- TASK A-16-1. 구매 월별 배송 지연율 확인
-- ==========================================================

SELECT purchase_month,
        COUNT(*) AS total_orders,
        COUNT(*) FILTER(WHERE is_delayed = 1) AS delayed_orders,
        ROUND(AVG(is_delayed::numeric)*100, 2)  AS delay_rate_pct
FROM analytics.v_order_delivery
GROUP BY purchase_month
ORDER BY purchase_month;

-- ==========================================================
-- TASK A-16-2. 배송 지연 급증 시기 진단
-- ==========================================================

SELECT purchase_month, customer_state,
        COUNT(*) AS total_orders,
        COUNT(*) FILTER(WHERE is_delayed = 1) AS delayed_orders,
        ROUND(AVG(is_delayed::numeric)*100, 2)  AS delay_rate_pct
FROM analytics.v_order_delivery
WHERE purchase_month  = '2018-03-01'
GROUP BY purchase_month, customer_state
ORDER BY delayed_orders DESC;

-- ==========================================================
-- TASK A-16-3. 주요 이상 시기 비교
-- ==========================================================

SELECT purchase_month, customer_state,
        COUNT(*) AS total_orders,
        COUNT(*) FILTER(WHERE is_delayed = 1) AS delayed_orders,
        ROUND(AVG(is_delayed::numeric)*100, 2)  AS delay_rate_pct
FROM analytics.v_order_delivery
WHERE purchase_month IN (
            '2017-11-01',
            '2018-02-01',
            '2018-03-01',
            '2018-04-01'
        )
GROUP BY purchase_month, customer_state
ORDER BY delayed_orders DESC;

-- ==========================================================
-- TASK A-17. Tableau용 지표 정의 확정
-- ==========================================================

SELECT
    ROUND(
        SUM(delayed_orders)::numeric
        / SUM(total_orders) * 100, 4
    ) AS state_benchmark_pct
FROM analytics.v_state_kpi;


SELECT
    ROUND(
        SUM(delayed_orders)::numeric
        / SUM(total_orders) * 100, 4
    ) AS seller_benchmark_pct
FROM analytics.v_seller_kpi;

SELECT
    ROUND(
        SUM(delayed_orders)::numeric
        / SUM(total_orders) * 100, 4
    ) AS category_benchmark_pct
FROM analytics.v_category_kpi;


SELECT (SELECT ROUND(
            SUM(delayed_orders)::numeric / SUM(total_orders) * 100, 4
        ) FROM analytics.v_state_kpi) AS state_benchmark_pct,
        (SELECT ROUND(
            SUM(delayed_orders)::numeric / SUM(total_orders) * 100, 4
        ) FROM analytics.v_seller_kpi) AS seller_benchmark_pct,
        (SELECT ROUND(
            SUM(delayed_orders)::numeric / SUM(total_orders) * 100, 4
        )
FROM analytics.v_category_kpi) AS category_benchmark_pct;
