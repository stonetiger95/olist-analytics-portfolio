/*
============================================================
Olist E-Commerce Analytics Portfolio

Project B - 상품군별 주간 주문 수량 예측
Day 01 - 데이터 검증 및 주간 시계열 구축
Database: PostgreSQL (olist)

[작업 내용]
1. 주문 상태와 구매일 범위 확인 (B-01~B-02)
2. 주간 연속성과 상품군별 관측 범위·변동성 확인 (B-03~B-05)
3. 학습 기간 상위 상품군 선정 및 예측용 뷰 구축 (B-06)

[분석 기준]
- 전체 기간: 2017-03-06 ~ 2018-08-19 (월요일 시작, 76주)
- 학습: 2017-03-06 ~ 2018-05-27 (64주)
- 최종 평가: 2018-05-28 ~ 2018-08-19 (12주)
- 목표변수: 구매 시점 기준 주문 상품 항목 수
- 취소·미완료 주문을 포함하므로 실제 판매 완료 수량이나 잠재 수요와 다르다.

[주요 검증 결과]
- 최종 뷰: analytics.v_weekly_category_demand
- 상품군 5개 × 76주 = 380행
============================================================
*/


-- ==========================================================
-- TASK B-01. 주문 상태별 건수 및 구매일 범위 확인
-- ==========================================================

-- [목적]
-- 주문 상태별 주문 건수와 최초·최종 구매일을 확인한다.
-- 이 단계는 원본 주문 전체를 대상으로 한다.

SELECT order_status,
    COUNT(*) AS order_count,
    MIN(order_purchase_timestamp::date) AS first_purchase_date,
    MAX(order_purchase_timestamp::date) AS last_purchase_date
FROM public.orders
GROUP BY order_status;


-- ==========================================================
-- TASK B-02. 전체 주간 주문량 및 주문 상태별 분포 확인
-- ==========================================================

-- [목적]
-- 구매일을 월요일 시작 주차로 묶어 전체 주문 건수와 상태별 건수를 비교한다.
-- 상태가 NULL이면 전체 건수에는 포함되지만 상태별 집계에는 포함되지 않는다.

SELECT date_trunc('week', order_purchase_timestamp)::date AS week_start,
    COUNT(*) AS all_orders,
    COUNT(*) FILTER (WHERE order_status = 'delivered') AS delivered_orders,
    COUNT(*) FILTER (WHERE order_status = 'canceled') AS canceled_orders,
    COUNT(*) FILTER (WHERE order_status NOT IN ('delivered', 'canceled')) AS other_orders
FROM orders
GROUP BY 1
ORDER BY 1;


-- ==========================================================
-- TASK B-03. 주간 시계열 연속성 및 결측 주차 확인
-- ==========================================================

-- [목적]
-- 분석 기간의 월요일 76개와 실제 주문 집계를 대조한다.
-- 집계 컬럼이 NULL인 행은 해당 주차에 주문 집계가 없음을 뜻한다.

WITH week_start_series AS (
    SELECT generate_series::date AS week_start
    FROM generate_series(
            '2017-03-06'::timestamp,
            '2018-08-13'::timestamp,
            interval '1 week'
    )
),
week_with_orders AS (
    SELECT date_trunc('week', order_purchase_timestamp)::date AS week_start,
        COUNT(*) AS all_orders,
        COUNT(*) FILTER (WHERE order_status = 'delivered') AS delivered_orders,
        COUNT(*) FILTER (WHERE order_status = 'canceled') AS canceled_orders,
        COUNT(*) FILTER (WHERE order_status NOT IN ('delivered', 'canceled')) AS other_orders
    FROM orders
    WHERE order_purchase_timestamp >= '2017-03-06'::timestamp
        AND order_purchase_timestamp < '2018-08-20'::timestamp
    GROUP BY 1
)
SELECT wss.week_start, wwo.all_orders, wwo.delivered_orders,
    wwo.canceled_orders, wwo.other_orders
FROM week_start_series wss
LEFT JOIN week_with_orders wwo
    ON wss.week_start = wwo.week_start
ORDER BY 1;


-- ==========================================================
-- TASK B-04. 상품군별 주문 상품 규모 및 활동 주차 확인
-- ==========================================================

-- [목적]
-- 주문 상품 행 수, 고유 주문 수, 주문이 관측된 주차 수를 상품군별로 비교한다.
-- 활동 주차 비율의 분모는 전체 76주다.

SELECT p.product_category_name,
    COUNT(*) AS total_items,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT date_trunc('week', o.order_purchase_timestamp::date)) AS active_week,
    ROUND(COUNT(DISTINCT date_trunc('week', o.order_purchase_timestamp::date))::numeric / 76 *100, 2) AS active_week_ratio
FROM orders o
JOIN order_items oi
    ON o.order_id = oi.order_id
JOIN products p
    ON oi.product_id = p.product_id
WHERE order_purchase_timestamp >= '2017-03-06'::timestamp
    AND order_purchase_timestamp < '2018-08-20'::timestamp
GROUP BY p.product_category_name
ORDER BY total_items DESC, active_week DESC;


-- ==========================================================
-- TASK B-05. 상품군별 주간 주문 수량 및 변동성 검증
-- ==========================================================

-- [목적]
-- 전체 기간 주문 상품 항목 수 상위 5개 상품군의 주간 평균, 표본 표준편차,
-- 최솟값·최댓값과 변동계수(cv = 표본 표준편차 / 평균)를 확인한다.
-- 거래가 없는 주차는 집계에서 제외될 수 있다. 이 순위는 탐색용이며,
-- B-06의 예측 대상 선정에는 학습 기간 순위를 사용한다.

WITH week_category_summary AS (
    SELECT p.product_category_name,
        date_trunc('week', o.order_purchase_timestamp)::date AS week_start,
        COUNT(*) AS weekly_items
    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    WHERE order_purchase_timestamp >= '2017-03-06'::timestamp
        AND order_purchase_timestamp < '2018-08-20'::timestamp
    GROUP BY 1, 2
)
SELECT product_category_name,
    COUNT(*) AS observed_weeks,
    AVG(weekly_items) AS mean_items,
    STDDEV_SAMP(weekly_items) AS std_items,
    MIN(weekly_items) AS min_items,
    MAX(weekly_items) AS max_items,
    ROUND(STDDEV_SAMP(weekly_items)::numeric / NULLIF(AVG(weekly_items), 0), 4) AS cv
FROM week_category_summary
GROUP BY product_category_name
ORDER BY SUM(weekly_items) DESC
LIMIT 5;


-- ==========================================================
-- TASK B-06. 예측 대상 상품군 선정 및 주간 수요 데이터 구축
-- ==========================================================

-- [목적]
-- 평가 기간의 주문량이 상품군 선택에 영향을 주지 않도록 학습 64주에서만
-- 상품군 이름이 있는 항목을 집계하고 상위 5개를 선정한다.
-- 항목 수가 같으면 상품군 이름의 오름차순으로 순위를 결정한다.
--
-- [뷰 구성]
-- analytics 스키마가 생성된 상태에서 실행한다.
-- 한 행은 상품군 1개와 월요일 시작 주차 1개의 조합이다.
-- product_category_name: 원본 상품군 이름
-- week_start: 구매일이 속한 주의 월요일 (date)
-- weekly_items: 해당 상품군·주차의 주문 상품 항목 수
-- 선정 상품군과 전체 76주를 조합하고, 주문 상품 집계가 없는 조합은 0으로 채운다.
-- 적재 누락도 0으로 표시될 수 있으므로 B-03에서 원천 주문의 주차 연속성을 확인한다.

CREATE OR REPLACE VIEW analytics.v_weekly_category_demand AS
WITH training AS (
    SELECT p.product_category_name
    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    WHERE order_purchase_timestamp >= '2017-03-06'::timestamp
        AND order_purchase_timestamp < '2018-05-28'::timestamp
        AND p.product_category_name IS NOT NULL
    GROUP BY 1
    ORDER BY COUNT(*) DESC, p.product_category_name ASC
    LIMIT 5
),
week_start_series AS (
    SELECT generate_series::date AS week_start
    FROM generate_series(
            '2017-03-06'::timestamp,
            '2018-08-13'::timestamp,
            interval '1 week'
    )
),
weekly_orders AS (
    SELECT p.product_category_name,
        date_trunc('week', o.order_purchase_timestamp)::date AS week_start,
        COUNT(*) AS weekly_items
    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    WHERE order_purchase_timestamp >= '2017-03-06'::timestamp
        AND order_purchase_timestamp < '2018-08-20'::timestamp
        AND p.product_category_name IN (SELECT product_category_name FROM training)
    GROUP BY 1, 2
)
SELECT
    t.product_category_name,
    w.week_start,
    COALESCE(o.weekly_items, 0) AS weekly_items
FROM training t
CROSS JOIN week_start_series w
LEFT JOIN weekly_orders o
    ON o.product_category_name = t.product_category_name
   AND o.week_start = w.week_start
ORDER BY w.week_start, t.product_category_name;

-- [검증 결과]
-- 기존 데이터에서는 최종 5개 상품군 모두 실제 주문이 76주에 걸쳐 관측됐다.
-- 같은 원본으로 실행하면 상품군별 total_weeks = 76, zero_weeks = 0이 기대된다.
-- 아래 주문 상품 합계는 전체 76주 기준이다.
-- cama_mesa_banho 10,735 / beleza_saude 9,174 / esporte_lazer 8,257
-- moveis_decoracao 7,669 / informatica_acessorios 7,584

SELECT product_category_name,
    COUNT(*) AS total_weeks,
    COUNT(*) FILTER (WHERE weekly_items = 0) AS zero_weeks,
    SUM(weekly_items) AS total_items
FROM analytics.v_weekly_category_demand
GROUP BY product_category_name
ORDER BY total_items DESC;