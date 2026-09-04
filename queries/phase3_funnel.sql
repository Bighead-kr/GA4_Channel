-- =============================================================================
-- Phase 3 — 채널별 퍼널
-- 실행 환경: BigQuery Console
-- 데이터: bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
-- 출처/해석: 노션 "GA4 유입 채널 성과 분석 — 포트폴리오" (source of truth)
-- =============================================================================


-- --------------------------------------------------------------------------
-- Q13. 단계 간 포함관계가 성립하는가? ★ Q12 전에 먼저
-- --------------------------------------------------------------------------
WITH funnel AS (
  SELECT
    user_pseudo_id,
    COUNTIF(event_name = 'view_item')        > 0 AS s1,
    COUNTIF(event_name = 'add_to_cart')      > 0 AS s2,
    COUNTIF(event_name = 'begin_checkout')   > 0 AS s3,
    COUNTIF(event_name = 'add_payment_info') > 0 AS s4,
    COUNTIF(event_name = 'purchase')         > 0 AS s5
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY 1
)
SELECT
  COUNTIF(s5)                  AS purchasers,
  COUNTIF(s5 AND NOT s4)       AS purchase_without_payment_info,
  COUNTIF(s5 AND NOT s3)       AS purchase_without_checkout,
  COUNTIF(s5 AND NOT s2)       AS purchase_without_cart,
  COUNTIF(s5 AND NOT s1)       AS purchase_without_view_item,
  COUNTIF(s3 AND NOT s2)       AS checkout_without_cart,
  COUNTIF(s2 AND NOT s1)       AS cart_without_view_item
FROM funnel;


-- --------------------------------------------------------------------------
-- Q12. 채널 × 5단계 퍼널 통과율
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
funnel AS (
  SELECT
    user_pseudo_id,
    COUNTIF(event_name = 'view_item')        > 0 AS s1,
    COUNTIF(event_name = 'add_to_cart')      > 0 AS s2,
    COUNTIF(event_name = 'begin_checkout')   > 0 AS s3,
    COUNTIF(event_name = 'add_payment_info') > 0 AS s4,
    COUNTIF(event_name = 'purchase')         > 0 AS s5
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY 1
)
SELECT
  c.channel_group,
  COUNT(*)                                                        AS users,
  COUNTIF(f.s1)                                                   AS view_item,
  COUNTIF(f.s2)                                                   AS add_to_cart,
  COUNTIF(f.s3)                                                   AS begin_checkout,
  COUNTIF(f.s4)                                                   AS add_payment_info,
  COUNTIF(f.s5)                                                   AS purchase,
  ROUND(100 * COUNTIF(f.s2) / NULLIF(COUNTIF(f.s1), 0), 1)        AS r1_view_to_cart,
  ROUND(100 * COUNTIF(f.s3) / NULLIF(COUNTIF(f.s2), 0), 1)        AS r2_cart_to_checkout,
  ROUND(100 * COUNTIF(f.s4) / NULLIF(COUNTIF(f.s3), 0), 1)        AS r3_checkout_to_payment,
  ROUND(100 * COUNTIF(f.s5) / NULLIF(COUNTIF(f.s4), 0), 1)        AS r4_payment_to_purchase,
  ROUND(100 * COUNTIF(f.s5) / NULLIF(COUNTIF(f.s1), 0), 2)        AS view_to_purchase,
  ROUND(100 * COUNTIF(f.s5) / COUNT(*), 2)                        AS user_to_purchase
FROM channel c
JOIN funnel f USING (user_pseudo_id)
GROUP BY 1
ORDER BY users DESC;
