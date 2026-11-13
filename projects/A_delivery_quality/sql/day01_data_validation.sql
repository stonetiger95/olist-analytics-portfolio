
/*
============================================================
Olist E-Commerce Analytics Portfolio

Day 01 - 데이터 구조 이해 및 배송 품질 KPI 산출
Date: 2026-11-10
Database: PostgreSQL (olist)

[작업 내용]
1. 원본 데이터 구조 및 적재 상태 확인
2. order_items 데이터 품질 및 참조 무결성 검증
3. 테이블별 주문 단위 중복 구조 확인
4. 배송 완료 주문의 날짜 데이터 검증
5. 배송 지연율 KPI 산출
6. 배송 지연 일수 기초 통계량 산출

[주요 분석 결과]
- 배송 완료 주문: 96,478건
- 실제 배송일 결측: 8건
- 분석 대상 주문: 96,470건
- 지연 배송 주문: 6,534건
- 배송 지연율: 6.77%
- 평균 지연 일수: 10.62일
- 최대 지연 일수: 188일

[다음 작업]
TASK A-07
- 배송 데이터 CSV 추출
- Python을 이용한 분포 분석
- Histogram 및 Boxplot 작성
============================================================
*/


-- ==========================================================
-- TASK A-01. 원본 데이터 구조 및 적재 상태 확인
-- ==========================================================

-- [목적]
-- Olist 원본 9개 테이블의 데이터 적재 상태 확인
-- 테이블별 행 수를 집계하여 누락 여부 점검

SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'geolocation', COUNT(*) FROM geolocation
UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'payments', COUNT(*) FROM payments
UNION ALL
SELECT 'product_category_name_translation', COUNT(*)
FROM product_category_name_translation
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'reviews', COUNT(*) FROM reviews
UNION ALL
SELECT 'sellers', COUNT(*) FROM sellers
ORDER BY table_name;


-- [추가 확인]
-- order_items 테이블의 컬럼명과 데이터 타입 확인
-- 초기 점검에서 데이터가 0행이어서 CSV 재적재 수행
-- 재적재 결과: 112,650행

SELECT
    ordinal_position,
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'order_items'
ORDER BY ordinal_position;



-- ==========================================================
-- TASK A-02. order_items 데이터 품질 검증
-- ==========================================================

-- [목적]
-- 주문 상품 데이터의 주요 식별자 결측 여부 확인
-- 전체 행 수와 고유 주문 수 비교
--
-- [검증 결과]
-- 전체 행 수: 112,650
-- 고유 주문 수: 98,666
-- 주요 식별자 결측: 0

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS unique_orders,
    COUNT(*) FILTER (
        WHERE order_id IS NULL
           OR product_id IS NULL
           OR seller_id IS NULL
    ) AS missing_keys
FROM public.order_items;


-- [추가 검증]
-- 1. orders에 존재하지 않는 주문 ID 확인
-- 2. (order_id, order_item_id) 중복 확인
-- 3. 가격·배송비의 결측 및 음수 확인
--
-- [검증 결과]
-- unmatched_orders: 0
-- duplicate_item_keys: 0
-- invalid_prices: 0

SELECT
    -- 참조 대상 주문이 없는 상품 행 수
    (
        SELECT COUNT(*)
        FROM order_items oi
        LEFT JOIN orders o
            ON oi.order_id = o.order_id
        WHERE o.order_id IS NULL
    ) AS unmatched_orders,

    -- 주문 내 상품 순번 중복 그룹 수
    (
        SELECT COUNT(*)
        FROM (
            SELECT order_id, order_item_id
            FROM order_items
            GROUP BY order_id, order_item_id
            HAVING COUNT(*) > 1
        ) t
    ) AS duplicate_item_keys,

    -- 가격 또는 배송비 이상값
    (
        SELECT COUNT(*)
        FROM order_items
        WHERE price IS NULL
           OR freight_value IS NULL
           OR price < 0
           OR freight_value < 0
    ) AS invalid_prices;



-- ==========================================================
-- TASK A-02 (추가). 테이블별 주문 다중성 검증
-- ==========================================================

-- [목적]
-- 주문별 상품·결제·리뷰 행 수 확인
-- 1:N 관계로 인한 JOIN 중복 집계 위험 파악
--
-- [주요 결과]
-- order_items: 복수 행 주문 9,803건
-- payments: 복수 행 주문 2,961건
-- reviews: 복수 행 주문 547건
--
-- [분석 시 유의사항]
-- 주문 단위 KPI 계산 시 각 테이블을 주문 단위로
-- 집계한 후 JOIN해야 중복 집계를 방지할 수 있음

WITH per_order AS (
    SELECT
        'order_items' AS table_name,
        order_id,
        COUNT(*) AS n
    FROM order_items
    GROUP BY order_id

    UNION ALL

    SELECT
        'payments',
        order_id,
        COUNT(*)
    FROM payments
    GROUP BY order_id

    UNION ALL

    SELECT
        'reviews',
        order_id,
        COUNT(*)
    FROM reviews
    GROUP BY order_id
)
SELECT
    table_name,
    SUM(n) AS total_rows,
    COUNT(*) AS unique_orders,
    COUNT(*) FILTER (WHERE n > 1) AS multi_row_orders,
    MAX(n) AS max_rows_per_order
FROM per_order
GROUP BY table_name
ORDER BY table_name;



-- ==========================================================
-- TASK A-03. 배송 날짜 데이터 탐색
-- ==========================================================

-- [목적]
-- 배송 완료 주문의 예상 배송일과 실제 배송일 확인
-- Timestamp 데이터의 날짜·시각 기록 방식 파악
--
-- [탐색 결과]
-- 예상 배송일은 자정(00:00:00)으로 표시됨
-- 실제 배송일에는 구체적인 배송 완료 시각이 존재
--
-- [주의]
-- LIMIT 10은 무작위 표본 추출이 아님
-- 전체 데이터의 특성을 단정할 수 없음

SELECT
    order_id,
    order_status,
    order_estimated_delivery_date,
    order_delivered_customer_date
FROM orders
WHERE order_status = 'delivered'
LIMIT 10;



-- ==========================================================
-- TASK A-04. 배송 데이터 품질 검증
-- ==========================================================

-- [목적]
-- 배송 완료 주문 중 배송 날짜 결측 여부 확인
-- 예상 배송일의 시각이 모두 자정인지 검증
--
-- [결과]
-- 배송 완료 주문: 96,478건
-- 실제 배송일 결측: 8건
-- 예상 배송일 결측: 0건
-- 예상 배송 시각 예외: 0건
--
-- [판단]
-- 실제 배송일 결측 8건은 지연 여부 판단 불가능
-- 배송 지연 분석에서 제외
-- 배송 지연 판정은 날짜 단위로 수행

SELECT
    COUNT(*) AS total_delivered,

    COUNT(*) FILTER (
        WHERE order_delivered_customer_date IS NULL
    ) AS missing_actual_date,

    COUNT(*) FILTER (
        WHERE order_estimated_delivery_date IS NULL
    ) AS missing_estimated_date,

    COUNT(*) FILTER (
        WHERE order_estimated_delivery_date::time != '00:00:00'
    ) AS non_midnight_estimated

FROM orders
WHERE order_status = 'delivered';



-- ==========================================================
-- TASK A-05. 배송 지연율 KPI 산출
-- ==========================================================

-- [분석 목적]
-- 배송 완료 주문 중 예상 배송일을 초과한 주문 비율 계산
--
-- [KPI 정의]
-- 분석 단위: 주문(order_id)
-- 분석 대상: delivered 상태이며 배송 날짜가 확인된 주문
-- 배송 지연: 실제 배송일 > 예상 배송일
-- 정시 배송: 실제 배송일 <= 예상 배송일
--
-- [검증 결과]
-- 분석 대상: 96,470건
-- 지연 배송: 6,534건
-- 정시·조기 배송: 89,936건
-- 배송 지연율: 6.77%


-- 방법 1. COUNT FILTER 활용

SELECT
    COUNT(*) AS total_orders,

    COUNT(*) FILTER (
        WHERE order_delivered_customer_date::date >
              order_estimated_delivery_date::date
    ) AS delayed_orders,

    COUNT(*) FILTER (
        WHERE order_delivered_customer_date::date <=
              order_estimated_delivery_date::date
    ) AS on_time_orders,

    COUNT(*) FILTER (
        WHERE order_delivered_customer_date::date >
              order_estimated_delivery_date::date
    )::float / COUNT(*) * 100 AS delay_rate

FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL;


-- 방법 2. CTE 활용
--
-- [개선 내용]
-- 배송 지연 여부를 0과 1의 이진변수로 정의
-- SUM(delayed): 지연 배송 주문 수
-- AVG(delayed): 전체 주문 중 지연 배송 비율
-- 중복되는 날짜 비교 조건을 줄임

WITH delivery AS (
    SELECT
        (order_delivered_customer_date::date >
         order_estimated_delivery_date::date)::int AS delayed
    FROM orders
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NOT NULL
      AND order_estimated_delivery_date IS NOT NULL
)
SELECT
    COUNT(*) AS total_orders,
    SUM(delayed) AS delayed_orders,
    COUNT(*) - SUM(delayed) AS on_time_orders,
    ROUND(AVG(delayed) * 100, 2) AS delay_rate_pct
FROM delivery;



-- ==========================================================
-- TASK A-06. 배송 지연 일수 기초 통계량
-- ==========================================================

-- [목적]
-- 배송 지연 발생 빈도뿐 아니라 지연 심각도 측정
--
-- [변수 정의]
-- delay_days = 실제 배송 날짜 - 예상 배송 날짜
--
-- delay_days > 0 : 지연 배송
-- delay_days = 0 : 예정일 당일 배송
-- delay_days < 0 : 조기 배송
--
-- [분석 대상]
-- 지연이 발생한 주문만 선택하여 통계량 계산
--
-- [결과]
-- 지연 주문: 6,534건
-- 평균 지연 일수: 10.62일
-- 최소 지연 일수: 1일
-- 최대 지연 일수: 188일
--
-- [해석 시 유의사항]
-- 평균 10.62일은 지연 주문만의 평균임
-- 최대 188일 사례가 존재하므로 분포 확인 필요
-- 평균만으로 일반적인 지연 수준을 판단하지 않음

WITH delivery AS (
    SELECT
        order_delivered_customer_date::date
        - order_estimated_delivery_date::date AS delay_days
    FROM orders
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NOT NULL
      AND order_estimated_delivery_date IS NOT NULL
)
SELECT
    COUNT(*) AS delayed_orders,
    ROUND(AVG(delay_days), 2) AS avg_delay_days,
    MIN(delay_days) AS min_delay_days,
    MAX(delay_days) AS max_delay_days
FROM delivery
WHERE delay_days > 0;



-- ==========================================================
-- TASK A-07. 배송 지연 일수 분포 분석 (Day 02 예정)
-- ==========================================================

-- [목적]
-- 평균·중앙값·백분위수 비교
-- 배송 지연 분포의 비대칭성과 극단값 확인
--
-- [예정 작업]
-- 1. 주문별 배송 지연 일수를 SQL로 추출
-- 2. 결과를 CSV 파일로 저장
-- 3. Python pandas로 데이터 로드
-- 4. 기술통계량 및 분위수 계산
-- 5. Histogram과 Boxplot 작성
-- 6. 이상치 및 분포 특성 해석
--
-- [예상 결과물]
-- 배송 지연 일수 분석용 CSV
-- 기술통계 요약표
-- Histogram 1개
-- Boxplot 1개
-- 분석 결과 해석
