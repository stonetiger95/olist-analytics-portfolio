# Olist E-Commerce Data Analytics

브라질 이커머스 플랫폼 Olist의 공개 데이터를 활용한 데이터 분석 포트폴리오입니다.

SQL을 활용한 데이터 검증과 분석용 데이터 구축, Python 기반 탐색적 분석 및 통계적 검증, Tableau 시각화를 통해 비즈니스 의사결정에 활용할 수 있는 인사이트를 도출하는 것을 목표로 합니다.

## Projects

| 프로젝트 | 주제 | 상태 |
|---|---|---|
| [**A. Delivery Quality**](projects/A_delivery_quality/README.md) | 배송 품질 진단 및 개선 우선순위 분석 | 완료 |
| B | 추후 선정 | 예정 |
| C | 추후 선정 | 예정 |
| D | 추후 선정 | 예정 |

## Project A — Delivery Quality Analysis

**분석 질문**

배송 지연은 고객 평가와 어떤 관계가 있으며, 어떤 지역·판매자·상품군을 우선 점검해야 할까요?

**기술 스택**

PostgreSQL · SQL · Python · pandas · SciPy · statsmodels · Tableau

**핵심 분석 결과**

| 지표 | 결과 |
|---|---:|
| 배송 품질 분석 주문 | 96,470건 |
| 배송 지연 주문 | 6,534건 |
| 전체 배송 지연율 | 6.77% |
| 고객 평가 분석 주문 | 95,299건 |
| 배송 지연 수준과 저평점의 연관성 | Cramér's V = 0.413 |
| 초과 지연 건수 최대 지역 | RJ (+658.5건) |

분석 결과, 배송 지연과 낮은 고객 평점 사이에 통계적으로 유의한 연관성이 확인되었습니다. 또한 지역·판매자·상품군 및 구매 시기에 따라 배송 품질의 차이가 관측되었습니다.

해당 결과는 관측적 연관성과 운영 점검 후보를 제시하며, 인과관계나 실제 개선 효과를 입증하는 것은 아닙니다.

**[배송 품질 모니터링](https://public.tableau.com/views/Olist_17945549244590/Olist) · [배송 개선 우선순위 진단](https://public.tableau.com/views/Olist_17945549244590/Olist_1)**

상세 분석 과정과 재현 코드는 `projects/A_delivery_quality/`에서 확인할 수 있습니다.

## Data

Olist Brazilian E-Commerce 공개 데이터셋을 사용했습니다.

원본 데이터는 PostgreSQL에 적재하여 분석했으며, 공개 저장소에는 분석 코드와 결과물 중심으로 제공합니다. 원본 데이터 다운로드 및 분석 환경 설정 방법은 프로젝트별 문서에 정리합니다.