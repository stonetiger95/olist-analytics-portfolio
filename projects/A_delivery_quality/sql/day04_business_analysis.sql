-- TASK D04-01. 지역별 배송 문제 진단

select  customer_state,
		total_orders,
		delayed_orders,
		delay_rate_pct,
		low_rating_rate_pct 
  from  analytics.v_state_kpi
 order 
 	by  delayed_orders desc 
 limit  10;

-- TASK D04-01-2. 지역별 초과 지연 건수 계산
with  benchmark as (
	select  SUM(delayed_orders)::numeric/SUM(total_orders) as overall_delay_rate
	  from  analytics.v_state_kpi
)
select  s.*,
		round(s.delayed_orders-(s.total_orders * b.overall_delay_rate),1) as excess_delayed_orders
  from  analytics.v_state_kpi s
 cross
  join  benchmark b
 order 
 	by  excess_delayed_orders desc; 

/*
지역 분석 결론  
전체 평균 대비 초과 지연 건수를 기준으로 RJ, BA, CE가 주요 개선 검토 지역으로 나타났다. 특히 RJ는 초과 지연 규모가 가장 크다. 
반면 AL 등 상대적으로 주문량이 적지만 지연율이 높은 지역은 별도 모니터링 대상으로 관리할 필요가 있다. 
선정 기준은 초기 운영 가정이며 실제 개선 효과를 의미하지 않는다.
*/

-- TASK D04-02-1. 판매자별 주문량 분포 확인

select  COUNT(*) AS seller_count,
		MIN(total_orders) AS min_orders,
	    -- 중앙값
		PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_orders) as p50,
    	-- 75백분위수
		PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY total_orders) as p75,
    	-- 90백분위수
		PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY total_orders) as p90,
	    MAX(total_orders) AS max_orders,
	    COUNT(*) FILTER (WHERE total_orders < 10) AS sellers_under_10,
		COUNT(*) FILTER (WHERE total_orders >= 30) AS sellers_30_plus,
		COUNT(*) FILTER (WHERE total_orders >= 100) AS sellers_100_plus
FROM analytics.v_seller_kpi;

-- TASK D04-02-2. 최소 주문 수 기준별 주문 커버리지
with order_coverage as (
	select  SUM(total_orders) as all_orders,
			SUM(total_orders) filter(where total_orders >= 30) as orders_30_plus,
			SUM(total_orders) filter(where total_orders >= 100) as orders_100_plus
	  from  analytics.v_seller_kpi
	  )
select  all_orders, orders_30_plus, orders_100_plus,
		round(orders_30_plus::numeric / all_orders *100, 2) as  orders_30_plus_coverage,
		round(orders_100_plus::numeric / all_orders *100, 2) as  orders_100_plus_coverage
  from  order_coverage;

-- TASK D04-02-3. 판매자별 초과 지연 건수 계산

with  benchmark as (
	select  SUM(delayed_orders)::numeric/SUM(total_orders) as overall_delay_rate
	  from  analytics.v_seller_kpi 
)
select  s.*,
		round(s.delayed_orders-(s.total_orders * b.overall_delay_rate),1) as excess_delayed_orders
  from  analytics.v_seller_kpi s
 cross
  join  benchmark b
 where  s.total_orders >= 30
   and  s.delayed_orders::numeric / s.total_orders > b.overall_delay_rate
 order 
 	by  excess_delayed_orders desc
 limit  10; 

-- TASK D04-02-4 — 판매자 소재 지역 분포 확인

select  count(*) as total_sellers,
		count(*) filter(where seller_state = 'SP') as sp_seller,
		round(
			count(*) filter(where seller_state = 'SP')::numeric /
			count(*) *100, 2 
		) as sp_seller_pct,
		SUM(total_orders) AS total_orders,
		round(
			SUM(total_orders) FILTER (WHERE seller_state = 'SP')::numeric / 
			SUM(total_orders)*100, 2
		) as sp_order_pct
  from  analytics.v_seller_kpi
 where  total_orders >= 30;

-- TASK D04-02-5. SP 판매자의 배송 목적지별 분석

with sellers_in_order as (
	select  *,
			count(*) over (partition by order_id) as seller_count
	  from  analytics.v_seller_order
)
select  sio.customer_state , 
		count(*) as total_orders, 
		SUM(sio.is_delayed) as delayed_orders,
		round(AVG(sio.is_delayed::numeric)*100, 2) as delay_rate_pct  
  from  analytics.v_seller_kpi s 
  join  sellers_in_order sio
    on  s.seller_id  = sio.seller_id 
 where  s.seller_state = 'SP'
   and  sio.seller_count = 1
   and  s.total_orders >= 30
 group
	by  customer_state
 order
	by  total_orders desc;

/*
- 판매자별 배송 품질 분석 결과

주문 30건 이상인 판매자 615명을 대상으로 배송 품질을 비교했으며, 이들이 전체 단일 판매자 주문의 83.17%를 차지함을 확인하였다.
초과 지연 건수 상위 10개 판매자 중 8개는 SP 소재였으나, SP 판매자가 분석 대상 주문의 73.04%를 담당한다는 점에서 이를 SP 판매자의 품질 문제로 단정하기는 어렵다.
SP 소재 판매자의 배송 목적지를 추가 분석한 결과, SP 목적지의 지연율은 4.48%인 반면 RJ 목적지는 14.29%로 나타났다. 
이는 판매자 소재지뿐 아니라 배송 목적지와의 조합을 고려한 운영 점검이 필요함을 시사한다.
다만 배송 지연의 구체적인 원인은 확인되지 않았으므로 해당 결과는 개선 후보를 선정하기 위한 탐색적 분석으로 해석한다.

*/

-- TASK D04-03. 상품군별 개선 우선순위
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

-- TASK D04-04-1 — 구매 월별 배송 지연율 확인

select  purchase_month, 
		count(*) as total_orders,
		count(*) filter(where is_delayed = 1) as delayed_orders,
		round(avg(is_delayed::numeric)*100, 2)  as delay_rate_pct 
  from  analytics.v_order_delivery
 group
 	by  purchase_month
 order
 	by  purchase_month;

-- TASK D04-04-2. 배송 지연 급증 시기 진단

select  purchase_month, customer_state,
		count(*) as total_orders,
		count(*) filter(where is_delayed = 1) as delayed_orders,
		round(avg(is_delayed::numeric)*100, 2)  as delay_rate_pct 
  from  analytics.v_order_delivery
 where  purchase_month  = '2018-03-01'
 group
 	by  purchase_month, customer_state 
 order 
 	by  delayed_orders desc;

-- TASK D04-04-3: 주요 이상 시기 비교

select  purchase_month, customer_state,
		count(*) as total_orders,
		count(*) filter(where is_delayed = 1) as delayed_orders,
		round(avg(is_delayed::numeric)*100, 2)  as delay_rate_pct 
  from  analytics.v_order_delivery
 WHERE  purchase_month IN (
		    '2017-11-01',
		    '2018-02-01',
		    '2018-03-01',
		    '2018-04-01'
		)
 group
 	by  purchase_month, customer_state 
 order 
 	by  delayed_orders desc;

-- TASK D04-05-1. Tableau용 지표 정의 확정

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


select  (SELECT ROUND(
    	    SUM(delayed_orders)::numeric / SUM(total_orders) * 100, 4
    	) FROM analytics.v_state_kpi) AS state_benchmark_pct,
    	(SELECT ROUND(
       		SUM(delayed_orders)::numeric / SUM(total_orders) * 100, 4
    	) FROM analytics.v_seller_kpi) AS seller_benchmark_pct,
    	(SELECT ROUND(
        	SUM(delayed_orders)::numeric / SUM(total_orders) * 100, 4
    	) 
  from  analytics.v_category_kpi) AS category_benchmark_pct;






