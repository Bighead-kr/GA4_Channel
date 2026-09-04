-- =============================================================================
-- Phase 2 — 채널별 볼륨
-- 실행 환경: BigQuery Console
-- 데이터: bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
-- 출처/해석: 노션 "GA4 유입 채널 성과 분석 — 포트폴리오" (source of truth)
-- =============================================================================


-- --------------------------------------------------------------------------
-- Q10. 채널별 볼륨 종합 — 유저·세션·퍼널 진입률
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
user_metrics AS (
  SELECT
    user_pseudo_id,
    COUNT(DISTINCT (SELECT value.int_value FROM UNNEST(event_params)
                    WHERE key = 'ga_session_id'))       AS sessions,
    COUNTIF(event_name = 'first_visit') > 0             AS is_new,
    COUNTIF(event_name = 'view_item')   > 0             AS reached_view_item
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY 1
)
SELECT
  c.channel_group,
  COUNT(*)                                                     AS users,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)             AS user_pct,
  COUNTIF(m.is_new)                                            AS new_users,
  SUM(m.sessions)                                              AS sessions,
  ROUND(100 * SUM(m.sessions) / SUM(SUM(m.sessions)) OVER (), 1) AS session_pct,
  ROUND(SUM(m.sessions) / COUNT(*), 2)                         AS sessions_per_user,
  ROUND(100 * COUNTIF(m.reached_view_item) / COUNT(*), 1)      AS view_item_rate
FROM channel c
JOIN user_metrics m USING (user_pseudo_id)
GROUP BY 1
ORDER BY users DESC;


-- --------------------------------------------------------------------------
-- Q11. 채널별 유입 시점이 다른가? (계절성 교란 점검)
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
first_seen AS (
  SELECT user_pseudo_id, MIN(event_date) AS first_date
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY 1
)
SELECT
  c.channel_group,
  COUNT(*)                                                          AS users,
  ROUND(100 * COUNTIF(f.first_date <  '20201201') / COUNT(*), 1)    AS nov_pct,
  ROUND(100 * COUNTIF(f.first_date BETWEEN '20201201' AND '20201231')
        / COUNT(*), 1)                                              AS dec_pct,
  ROUND(100 * COUNTIF(f.first_date >= '20210101') / COUNT(*), 1)    AS jan_pct
FROM channel c
JOIN first_seen f USING (user_pseudo_id)
GROUP BY 1
ORDER BY users DESC;
