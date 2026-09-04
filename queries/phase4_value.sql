-- =============================================================================
-- Phase 4 — 채널별 가치 (전환율·객단가·ARPU)
-- 실행 환경: BigQuery Console
-- 데이터: bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
-- 출처/해석: 노션 "GA4 유입 채널 성과 분석 — 포트폴리오" (source of truth)
-- =============================================================================


-- --------------------------------------------------------------------------
-- Q14. 채널별 가치 — 전환율 · 객단가 · ARPU
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
    ecommerce.transaction_id            AS txn,
    ecommerce.purchase_revenue_in_usd   AS revenue,
    ROW_NUMBER() OVER (
      PARTITION BY ecommerce.transaction_id
      ORDER BY event_timestamp ASC
    ) AS dup_rn
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'purchase'
),
kept AS (
  SELECT user_pseudo_id, revenue
  FROM purchases
  WHERE txn IS NULL
     OR txn = '(not set)'
     OR dup_rn = 1
)
SELECT
  c.channel_group,
  COUNT(DISTINCT c.user_pseudo_id)                                AS users,
  ROUND(100 * COUNT(DISTINCT c.user_pseudo_id)
        / SUM(COUNT(DISTINCT c.user_pseudo_id)) OVER (), 1)       AS user_share_pct,
  COUNT(DISTINCT k.user_pseudo_id)                                AS buyers,
  COUNT(k.revenue)                                                AS orders,
  ROUND(SUM(k.revenue), 2)                                        AS revenue,
  ROUND(100 * SUM(k.revenue) / SUM(SUM(k.revenue)) OVER (), 1)    AS revenue_share_pct,
  ROUND(100 * COUNT(DISTINCT k.user_pseudo_id)
        / COUNT(DISTINCT c.user_pseudo_id), 2)                    AS cvr_pct,
  ROUND(SUM(k.revenue) / NULLIF(COUNT(k.revenue), 0), 2)          AS aov,
  ROUND(SUM(k.revenue) / COUNT(DISTINCT c.user_pseudo_id), 2)     AS arpu
FROM channel c
LEFT JOIN kept k USING (user_pseudo_id)
GROUP BY 1
ORDER BY users DESC;


-- --------------------------------------------------------------------------
-- Q15. 객단가 차이가 진짜인가, 구성 효과인가? ★ Q14와 같이 본다
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
    ecommerce.transaction_id            AS txn,
    ecommerce.purchase_revenue_in_usd   AS revenue,
    ROW_NUMBER() OVER (
      PARTITION BY ecommerce.transaction_id
      ORDER BY event_timestamp ASC
    ) AS dup_rn
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'purchase'
),
kept_valid AS (
  SELECT user_pseudo_id, revenue
  FROM purchases
  WHERE txn IS NOT NULL
    AND txn != '(not set)'
    AND dup_rn = 1
)
SELECT
  c.channel_group,
  COUNT(k.revenue)                                       AS orders_valid,
  ROUND(SUM(k.revenue), 2)                               AS revenue_valid,
  ROUND(SUM(k.revenue) / NULLIF(COUNT(k.revenue), 0), 2) AS aov_valid
FROM channel c
LEFT JOIN kept_valid k USING (user_pseudo_id)
GROUP BY 1
ORDER BY orders_valid DESC;


-- --------------------------------------------------------------------------
-- Q16. Paid의 높은 객단가가 소수 고액 주문 때문은 아닌가? ★ 견고성 점검
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
    ecommerce.transaction_id            AS txn,
    ecommerce.purchase_revenue_in_usd   AS revenue,
    ROW_NUMBER() OVER (
      PARTITION BY ecommerce.transaction_id
      ORDER BY event_timestamp ASC
    ) AS dup_rn
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'purchase'
),
kept_valid AS (
  SELECT user_pseudo_id, revenue
  FROM purchases
  WHERE txn IS NOT NULL AND txn != '(not set)' AND dup_rn = 1
)
SELECT
  c.channel_group,
  COUNT(*)                                                 AS orders,
  ROUND(AVG(k.revenue), 2)                                 AS mean,
  ROUND(APPROX_QUANTILES(k.revenue, 100)[OFFSET(25)], 2)   AS p25,
  ROUND(APPROX_QUANTILES(k.revenue, 100)[OFFSET(50)], 2)   AS median,
  ROUND(APPROX_QUANTILES(k.revenue, 100)[OFFSET(75)], 2)   AS p75,
  ROUND(APPROX_QUANTILES(k.revenue, 100)[OFFSET(95)], 2)   AS p95,
  ROUND(MAX(k.revenue), 2)                                 AS max_order
FROM channel c
JOIN kept_valid k USING (user_pseudo_id)
GROUP BY 1
ORDER BY median DESC;
