-- =============================================================================
-- Phase 1 — 데이터 이해 및 정의 확정 (세션·신규유저·채널귀속·구매)
-- 실행 환경: BigQuery Console
-- 데이터: bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
-- 출처/해석: 노션 "GA4 유입 채널 성과 분석 — 포트폴리오" (source of truth)
-- =============================================================================


-- --------------------------------------------------------------------------
-- Q1. 데이터의 규모와 실제 기간은?
-- --------------------------------------------------------------------------
SELECT
  MIN(event_date) AS first_date,
  MAX(event_date) AS last_date,
  COUNT(*)                        AS events,
  COUNT(DISTINCT user_pseudo_id)  AS users,
  COUNT(DISTINCT event_date)      AS days
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131';


-- --------------------------------------------------------------------------
-- Q2. 어떤 이벤트가 얼마나 찍혀 있는가?
-- --------------------------------------------------------------------------
SELECT
  event_name,
  COUNT(*)                       AS events,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
GROUP BY 1
ORDER BY events DESC;


-- --------------------------------------------------------------------------
-- Q3. `event_params`에는 어떤 키가 들어 있는가?
-- --------------------------------------------------------------------------
SELECT
  p.key,
  COUNT(*) AS cnt
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`,
  UNNEST(event_params) AS p
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
GROUP BY 1
ORDER BY cnt DESC;


-- --------------------------------------------------------------------------
-- Q3b. 세션 단위 채널은 어떤 이벤트에 붙는가?
-- --------------------------------------------------------------------------
SELECT
  event_name,
  COUNT(*) AS events,
  COUNTIF((SELECT value.string_value FROM UNNEST(event_params)
           WHERE key = 'source') IS NOT NULL) AS has_source,
  COUNTIF((SELECT value.string_value FROM UNNEST(event_params)
           WHERE key = 'medium') IS NOT NULL) AS has_medium
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
GROUP BY 1
ORDER BY events DESC;


-- --------------------------------------------------------------------------
-- Q3c. 유저 레벨 채널과 세션 레벨 채널은 얼마나 다른가?
-- --------------------------------------------------------------------------
WITH e AS (
  SELECT
    traffic_source.source AS user_source,
    traffic_source.medium AS user_medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS ev_source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS ev_medium
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
)
SELECT
  COUNT(*) AS events_with_session_source,
  COUNTIF(ev_source != user_source OR ev_medium != user_medium) AS mismatched,
  ROUND(100 * COUNTIF(ev_source != user_source OR ev_medium != user_medium)
        / COUNT(*), 2) AS mismatch_pct
FROM e
WHERE ev_source IS NOT NULL;


-- --------------------------------------------------------------------------
-- Q3d. 유입 채널이 2개 이상인 유저는 얼마나 되는가? ★ 결정적
-- --------------------------------------------------------------------------
SELECT
  n_sources,
  COUNT(*) AS users
FROM (
  SELECT
    user_pseudo_id,
    COUNT(DISTINCT CONCAT(
      IFNULL((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source'), ''), '|',
      IFNULL((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '')
    )) AS n_sources
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') IS NOT NULL
  GROUP BY 1
)
GROUP BY 1
ORDER BY 1;


-- --------------------------------------------------------------------------
-- Q4. 채널(source / medium) 값의 실태는?
-- --------------------------------------------------------------------------
SELECT
  traffic_source.source,
  traffic_source.medium,
  traffic_source.name,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
GROUP BY 1, 2, 3
ORDER BY users DESC
LIMIT 50;


-- --------------------------------------------------------------------------
-- Q5. `traffic_source`는 유저 단위로 고정인가? (채널 귀속 근거)
-- --------------------------------------------------------------------------
-- [Q5 쿼리 1]
SELECT COUNT(*) AS users_with_multiple_sources
FROM (
  SELECT user_pseudo_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY 1
  HAVING COUNT(DISTINCT CONCAT(
           IFNULL(traffic_source.source, ''), '|',
           IFNULL(traffic_source.medium, '')
         )) > 1
);

-- [Q5b] first-touch 채널 고정 — 이후 Phase 2~5의 모든 쿼리가 이 CTE 패턴을 재사용한다.
--       검증: users 합계 = 270,154 (전체 유저 수)
WITH first_touch AS (
  SELECT
    user_pseudo_id,
    traffic_source.source AS source,
    traffic_source.medium AS medium,
    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id
      ORDER BY event_timestamp ASC
    ) AS rn
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
)
SELECT
  CASE
    WHEN source = 'shop.googlemerchandisestore.com'      THEN 'Self-referral'
    WHEN medium IN ('<Other>', '(data deleted)')          THEN 'Unknown'
    WHEN medium = 'organic'                               THEN 'Organic Search'
    WHEN medium = 'cpc'                                   THEN 'Paid Search'
    WHEN medium = 'referral'                              THEN 'Referral'
    WHEN medium = '(none)'                                THEN 'Direct'
    ELSE 'Other'
  END AS channel_group,
  COUNT(*) AS users,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM first_touch
WHERE rn = 1
GROUP BY 1
ORDER BY users DESC;


-- --------------------------------------------------------------------------
-- Q6. 세션은 어떻게 셀 것인가?
-- --------------------------------------------------------------------------
-- [Q6 쿼리 1]
SELECT
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(s.value.int_value AS STRING))) AS sessions,
  COUNT(DISTINCT user_pseudo_id)                                                 AS users
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`,
  UNNEST(event_params) AS s
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  AND s.key = 'ga_session_id';

-- [Q6 쿼리 2]
SELECT
  COUNTIF((SELECT value.int_value FROM UNNEST(event_params)
           WHERE key = 'ga_session_id') IS NULL) AS events_without_session_id,
  COUNT(*)                                       AS total_events
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131';


-- --------------------------------------------------------------------------
-- Q7. 신규 유저는 무엇으로 정의하는가?
-- --------------------------------------------------------------------------
SELECT
  COUNT(DISTINCT user_pseudo_id)                                       AS all_users,
  COUNT(DISTINCT IF(event_name = 'first_visit',   user_pseudo_id, NULL)) AS first_visit_users,
  COUNT(DISTINCT IF(event_name = 'session_start', user_pseudo_id, NULL)) AS session_start_users
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131';


-- --------------------------------------------------------------------------
-- Q8. 구매는 무엇으로 정의하는가?
-- --------------------------------------------------------------------------
-- [Q8 쿼리 1]
SELECT
  event_name,
  COUNT(*)                                              AS events,
  COUNT(DISTINCT ecommerce.transaction_id)              AS transactions,
  COUNTIF(ecommerce.purchase_revenue_in_usd IS NULL)    AS revenue_null,
  ROUND(SUM(ecommerce.purchase_revenue_in_usd), 2)      AS revenue_usd
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  AND event_name IN ('purchase', 'in_app_purchase', 'refund')
GROUP BY 1;

-- [Q8 쿼리 2]
SELECT
  COUNT(*)                                 AS purchase_events,
  COUNT(DISTINCT ecommerce.transaction_id) AS unique_transactions
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  AND event_name = 'purchase';


-- --------------------------------------------------------------------------
-- Q8b. 1,240건은 중복인가 결측인가? ★ 구매 정의의 핵심
-- --------------------------------------------------------------------------
SELECT
  COUNT(*)                                            AS purchase_events,
  COUNTIF(ecommerce.transaction_id IS NULL)           AS txn_null,
  COUNTIF(ecommerce.transaction_id = '(not set)')     AS txn_not_set,
  COUNT(DISTINCT ecommerce.transaction_id)            AS unique_txn
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  AND event_name = 'purchase';


-- --------------------------------------------------------------------------
-- Q8c. 중복은 몇 번씩 찍혔는가?
-- --------------------------------------------------------------------------
SELECT
  events_per_txn,
  COUNT(*) AS transactions
FROM (
  SELECT
    ecommerce.transaction_id AS txn,
    COUNT(*)                 AS events_per_txn
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'purchase'
    AND ecommerce.transaction_id IS NOT NULL
  GROUP BY 1
)
GROUP BY 1
ORDER BY 1;


-- --------------------------------------------------------------------------
-- Q8d. 중복 제거하면 매출이 얼마나 변하는가?
-- --------------------------------------------------------------------------
WITH dedup AS (
  SELECT
    ecommerce.transaction_id            AS txn,
    ecommerce.purchase_revenue_in_usd   AS revenue,
    ROW_NUMBER() OVER (
      PARTITION BY ecommerce.transaction_id
      ORDER BY event_timestamp ASC
    ) AS rn
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'purchase'
    AND ecommerce.transaction_id IS NOT NULL
)
SELECT
  ROUND(SUM(revenue), 2)                        AS revenue_raw,
  ROUND(SUM(IF(rn = 1, revenue, 0)), 2)         AS revenue_dedup,
  ROUND(100 * (SUM(revenue) - SUM(IF(rn = 1, revenue, 0)))
        / SUM(revenue), 1)                      AS overstated_pct
FROM dedup;


-- --------------------------------------------------------------------------
-- Q8e. 진짜 중복만 제거했을 때의 매출 (Q8d 수정본)
-- --------------------------------------------------------------------------
WITH p AS (
  SELECT
    ecommerce.transaction_id           AS txn,
    ecommerce.purchase_revenue_in_usd  AS revenue,
    ROW_NUMBER() OVER (
      PARTITION BY ecommerce.transaction_id
      ORDER BY event_timestamp ASC
    ) AS rn
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'purchase'
    AND ecommerce.transaction_id IS NOT NULL
    AND ecommerce.transaction_id != '(not set)'   -- ← Q8d에 빠졌던 조건
)
SELECT
  COUNT(*)                                       AS events,
  COUNTIF(rn = 1)                                AS unique_transactions,
  ROUND(SUM(revenue), 2)                         AS revenue_raw,
  ROUND(SUM(IF(rn = 1, revenue, 0)), 2)          AS revenue_dedup,
  ROUND(100 * (SUM(revenue) - SUM(IF(rn = 1, revenue, 0)))
        / SUM(revenue), 2)                       AS overstated_pct
FROM p;


-- --------------------------------------------------------------------------
-- Q8f. 식별불가 구매 906건은 얼마짜리인가?
-- --------------------------------------------------------------------------
SELECT
  CASE
    WHEN ecommerce.transaction_id IS NULL       THEN 'null'
    WHEN ecommerce.transaction_id = '(not set)' THEN 'not set'
    ELSE 'valid'
  END                                              AS txn_status,
  COUNT(*)                                         AS events,
  COUNT(DISTINCT user_pseudo_id)                   AS users,
  ROUND(SUM(ecommerce.purchase_revenue_in_usd), 2) AS revenue,
  ROUND(AVG(ecommerce.purchase_revenue_in_usd), 2) AS avg_revenue
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  AND event_name = 'purchase'
GROUP BY 1
ORDER BY events DESC;


-- --------------------------------------------------------------------------
-- Q8g. 이 데이터 품질 문제가 채널 비교를 왜곡하는가? ★ 가장 중요
-- --------------------------------------------------------------------------
WITH first_touch AS (
  SELECT
    user_pseudo_id,
    traffic_source.source AS source,
    traffic_source.medium AS medium,
    ROW_NUMBER() OVER (PARTITION BY user_pseudo_id ORDER BY event_timestamp ASC) AS rn
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),
channel AS (
  SELECT
    user_pseudo_id,
    CASE
      WHEN source = 'shop.googlemerchandisestore.com'     THEN 'Self-referral'
      WHEN medium IN ('<Other>', '(data deleted)')         THEN 'Unknown'
      WHEN medium = 'organic'                              THEN 'Organic Search'
      WHEN medium = 'cpc'                                  THEN 'Paid Search'
      WHEN medium = 'referral'                             THEN 'Referral'
      WHEN medium = '(none)'                               THEN 'Direct'
      ELSE 'Other'
    END AS channel_group
  FROM first_touch
  WHERE rn = 1
),
purchases AS (
  SELECT
    user_pseudo_id,
    CASE
      WHEN ecommerce.transaction_id IS NULL       THEN 'unidentifiable'
      WHEN ecommerce.transaction_id = '(not set)' THEN 'unidentifiable'
      ELSE 'valid'
    END AS txn_status
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'purchase'
)
SELECT
  c.channel_group,
  COUNT(*)                                        AS purchase_events,
  COUNTIF(p.txn_status = 'unidentifiable')        AS unidentifiable,
  ROUND(100 * COUNTIF(p.txn_status = 'unidentifiable')
        / COUNT(*), 1)                            AS unidentifiable_pct
FROM purchases p
JOIN channel c USING (user_pseudo_id)
GROUP BY 1
ORDER BY purchase_events DESC;


-- --------------------------------------------------------------------------
-- Q7. 신규 유저 정의 — 별도 결과 없음
--   위 쿼리는 확인용. 숫자는 Q2에 이미 존재:
--   all_users 270,154 / first_visit_users 257,314 / session_start_users 267,116
--   결정: 신규 유저 = 관측 기간 내 first_visit 이벤트가 있는 user_pseudo_id (257,314명, 95.2%)
--
-- Q9. (direct)/(none) 트래픽 — 별도 쿼리 미실행
--   Q5b가 이미 답함: Direct = 64,109명 (23.7%).
--   결정: Direct는 별도 그룹으로 유지하되 투자 우선순위 제안 대상에서는 제외
--         (돈으로 살 수 있는 채널이 아님).
-- --------------------------------------------------------------------------
