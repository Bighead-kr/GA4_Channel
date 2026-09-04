-- =============================================================================
-- Phase 5 — 채널별 코호트·리텐션
-- 실행 환경: BigQuery Console (Phase 1~4와 동일)
-- 데이터   : bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
-- =============================================================================
--
-- 정의 (Phase 1에서 확정)
--   신규 유저 : 관측 기간 내 first_visit 이벤트가 있는 user_pseudo_id (257,314명)
--   채널      : first-touch, 유저별 최초 이벤트의 traffic_source, medium 주축 6그룹
--   재방문    : 해당 상대 주차에 session_start 이벤트 >= 1건
--
-- 주차 정의
--   기준일 2020-11-01(일요일). DATE_DIFF(..., WEEK(SUNDAY))로 절대 주차 계산.
--   W0 = 유입 주. rel_week = 활동 주차 - 코호트 주차.
--
-- 코호트 범위
--   Q17 (전체 히트맵)      : cohort_week 0~4 = first_visit 2020-11-01 ~ 12-05, 5개 코호트.
--                            → 가장 늦은 코호트도 W8까지 완전 관측 (활동 주차 최대 13).
--   Q18/Q19 (채널 비교)   : "11월 코호트" = cohort_week 0~3 = first_visit 2020-11-01 ~ 11-28.
--                            채널별 셀 크기를 키우려고 4개 코호트를 하나로 묶음.
--
-- 실행 순서: S1(검증) → Q17 → Q18 → Q19.
-- 결과는 노션 3-4 섹션 해당 자리에 붙여넣는다.
-- =============================================================================


-- =============================================================================
-- 공통 CTE 블록 (S1·Q17·Q18·Q19 모두 이 블록으로 시작한다)
-- =============================================================================
-- WITH
-- first_touch AS (
--   SELECT
--     user_pseudo_id,
--     traffic_source.source AS source,
--     traffic_source.medium AS medium,
--     ROW_NUMBER() OVER (PARTITION BY user_pseudo_id ORDER BY event_timestamp ASC) AS rn
--   FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
--   WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
-- ),
-- channel AS (
--   SELECT
--     user_pseudo_id,
--     CASE
--       WHEN source = 'shop.googlemerchandisestore.com' THEN 'Self-referral'
--       WHEN medium IN ('<Other>', '(data deleted)')     THEN 'Unknown'
--       WHEN medium = 'organic'                          THEN 'Organic Search'
--       WHEN medium = 'cpc'                              THEN 'Paid Search'
--       WHEN medium = 'referral'                         THEN 'Referral'
--       WHEN medium = '(none)'                           THEN 'Direct'
--       ELSE 'Other'
--     END AS channel_group
--   FROM first_touch
--   WHERE rn = 1
-- ),
-- cohort AS (   -- 신규 유저의 유입 주차
--   SELECT
--     user_pseudo_id,
--     MIN(PARSE_DATE('%Y%m%d', event_date)) AS first_visit_date,
--     DATE_DIFF(MIN(PARSE_DATE('%Y%m%d', event_date)), DATE '2020-11-01', WEEK(SUNDAY)) AS cohort_week
--   FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
--   WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
--     AND event_name = 'first_visit'
--   GROUP BY 1
-- ),
-- activity AS (   -- 유저 x 재방문(session_start) 주차
--   SELECT DISTINCT
--     user_pseudo_id,
--     DATE_DIFF(PARSE_DATE('%Y%m%d', event_date), DATE '2020-11-01', WEEK(SUNDAY)) AS activity_week
--   FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
--   WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
--     AND event_name = 'session_start'
-- ),
-- base AS (   -- 코호트(분모) LEFT JOIN 재방문 주차
--   SELECT
--     co.user_pseudo_id,
--     ch.channel_group,
--     co.cohort_week,
--     a.activity_week - co.cohort_week AS rel_week
--   FROM cohort co
--   JOIN channel ch USING (user_pseudo_id)
--   LEFT JOIN activity a USING (user_pseudo_id)
-- )


-- =============================================================================
-- S1. 검증 쿼리 — Q17~Q19 이전에 먼저 실행
-- =============================================================================
-- 확인 사항
--   total_new_users       = 257,314 (Phase 1 신규 유저 수와 일치해야 함)
--   nov_cohort            : 11월(cohort_week 0~3) 코호트 크기  → Q18/Q19 분모 합
--   heatmap_cohort        : cohort_week 0~4 코호트 크기        → Q17 분모 합
--   w0_retention_pct      : 정의상 100%에 가까워야 함(≈99%). 나머지는 session_start
--                           미발화 유저(Phase 1 Q2 ⑥, 약 1%).
--   neg_relweek_users     : first_visit보다 앞선 session_start를 가진 유저. 소수여야 정상.
--   no_session_start_users: first_visit은 있으나 session_start가 아예 없는 유저.
-- -----------------------------------------------------------------------------
WITH
first_touch AS (
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
      WHEN source = 'shop.googlemerchandisestore.com' THEN 'Self-referral'
      WHEN medium IN ('<Other>', '(data deleted)')     THEN 'Unknown'
      WHEN medium = 'organic'                          THEN 'Organic Search'
      WHEN medium = 'cpc'                              THEN 'Paid Search'
      WHEN medium = 'referral'                         THEN 'Referral'
      WHEN medium = '(none)'                           THEN 'Direct'
      ELSE 'Other'
    END AS channel_group
  FROM first_touch
  WHERE rn = 1
),
cohort AS (
  SELECT
    user_pseudo_id,
    MIN(PARSE_DATE('%Y%m%d', event_date)) AS first_visit_date,
    DATE_DIFF(MIN(PARSE_DATE('%Y%m%d', event_date)), DATE '2020-11-01', WEEK(SUNDAY)) AS cohort_week
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'first_visit'
  GROUP BY 1
),
activity AS (
  SELECT DISTINCT
    user_pseudo_id,
    DATE_DIFF(PARSE_DATE('%Y%m%d', event_date), DATE '2020-11-01', WEEK(SUNDAY)) AS activity_week
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'session_start'
),
base AS (
  SELECT
    co.user_pseudo_id,
    ch.channel_group,
    co.cohort_week,
    a.activity_week - co.cohort_week AS rel_week
  FROM cohort co
  JOIN channel ch USING (user_pseudo_id)
  LEFT JOIN activity a USING (user_pseudo_id)
)
SELECT
  COUNT(DISTINCT user_pseudo_id)                                             AS total_new_users,
  COUNT(DISTINCT IF(cohort_week BETWEEN 0 AND 3, user_pseudo_id, NULL))      AS nov_cohort,
  COUNT(DISTINCT IF(cohort_week BETWEEN 0 AND 4, user_pseudo_id, NULL))      AS heatmap_cohort,
  ROUND(100 * COUNT(DISTINCT IF(rel_week = 0, user_pseudo_id, NULL))
            / COUNT(DISTINCT user_pseudo_id), 2)                            AS w0_retention_pct,
  COUNT(DISTINCT IF(rel_week < 0, user_pseudo_id, NULL))                     AS neg_relweek_users,
  COUNT(DISTINCT IF(rel_week IS NULL, user_pseudo_id, NULL))                 AS no_session_start_users
FROM base;


-- =============================================================================
-- Q17. 전체 코호트 리텐션 (히트맵용, long format)
--   행 = 코호트 주차(0~4) x 상대 주차(0~8) = 45행
--   retention_pct = 해당 코호트에서 rel_week 주차에 재방문한 유저 비율
-- =============================================================================
WITH
first_touch AS (
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
      WHEN source = 'shop.googlemerchandisestore.com' THEN 'Self-referral'
      WHEN medium IN ('<Other>', '(data deleted)')     THEN 'Unknown'
      WHEN medium = 'organic'                          THEN 'Organic Search'
      WHEN medium = 'cpc'                              THEN 'Paid Search'
      WHEN medium = 'referral'                         THEN 'Referral'
      WHEN medium = '(none)'                           THEN 'Direct'
      ELSE 'Other'
    END AS channel_group
  FROM first_touch
  WHERE rn = 1
),
cohort AS (
  SELECT
    user_pseudo_id,
    DATE_DIFF(MIN(PARSE_DATE('%Y%m%d', event_date)), DATE '2020-11-01', WEEK(SUNDAY)) AS cohort_week
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'first_visit'
  GROUP BY 1
),
activity AS (
  SELECT DISTINCT
    user_pseudo_id,
    DATE_DIFF(PARSE_DATE('%Y%m%d', event_date), DATE '2020-11-01', WEEK(SUNDAY)) AS activity_week
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'session_start'
),
base AS (
  SELECT
    co.user_pseudo_id,
    co.cohort_week,
    a.activity_week - co.cohort_week AS rel_week
  FROM cohort co
  JOIN channel ch USING (user_pseudo_id)   -- 6그룹 분할 확인용 조인 (Other 없음)
  LEFT JOIN activity a USING (user_pseudo_id)
),
cohort_sizes AS (
  SELECT cohort_week, COUNT(DISTINCT user_pseudo_id) AS cohort_size
  FROM base
  GROUP BY 1
),
rel_weeks AS (
  SELECT rw FROM UNNEST(GENERATE_ARRAY(0, 8)) AS rw
)
SELECT
  cs.cohort_week,
  FORMAT_DATE('%Y-%m-%d', DATE_ADD(DATE '2020-11-01', INTERVAL cs.cohort_week WEEK)) AS cohort_week_start,
  cs.cohort_size,
  r.rw AS rel_week,
  COUNT(DISTINCT IF(b.rel_week = r.rw, b.user_pseudo_id, NULL)) AS retained_users,
  ROUND(100 * COUNT(DISTINCT IF(b.rel_week = r.rw, b.user_pseudo_id, NULL)) / cs.cohort_size, 2) AS retention_pct
FROM cohort_sizes cs
CROSS JOIN rel_weeks r
JOIN base b ON b.cohort_week = cs.cohort_week
WHERE cs.cohort_week BETWEEN 0 AND 4
GROUP BY 1, 2, 3, 4
ORDER BY 1, 4;


-- =============================================================================
-- Q18. 채널 x 상대 주차 리텐션 (곡선용, long format)
--   코호트 = 11월(cohort_week 0~3) 유입 전체를 하나로 묶음
--   행 = 채널(6) x 상대 주차(0~8) = 54행
-- =============================================================================
WITH
first_touch AS (
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
      WHEN source = 'shop.googlemerchandisestore.com' THEN 'Self-referral'
      WHEN medium IN ('<Other>', '(data deleted)')     THEN 'Unknown'
      WHEN medium = 'organic'                          THEN 'Organic Search'
      WHEN medium = 'cpc'                              THEN 'Paid Search'
      WHEN medium = 'referral'                         THEN 'Referral'
      WHEN medium = '(none)'                           THEN 'Direct'
      ELSE 'Other'
    END AS channel_group
  FROM first_touch
  WHERE rn = 1
),
cohort AS (
  SELECT
    user_pseudo_id,
    DATE_DIFF(MIN(PARSE_DATE('%Y%m%d', event_date)), DATE '2020-11-01', WEEK(SUNDAY)) AS cohort_week
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'first_visit'
  GROUP BY 1
),
activity AS (
  SELECT DISTINCT
    user_pseudo_id,
    DATE_DIFF(PARSE_DATE('%Y%m%d', event_date), DATE '2020-11-01', WEEK(SUNDAY)) AS activity_week
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'session_start'
),
base AS (
  SELECT
    co.user_pseudo_id,
    ch.channel_group,
    co.cohort_week,
    a.activity_week - co.cohort_week AS rel_week
  FROM cohort co
  JOIN channel ch USING (user_pseudo_id)
  LEFT JOIN activity a USING (user_pseudo_id)
  WHERE co.cohort_week BETWEEN 0 AND 3
),
cohort_sizes AS (
  SELECT channel_group, COUNT(DISTINCT user_pseudo_id) AS cohort_size
  FROM base
  GROUP BY 1
),
rel_weeks AS (
  SELECT rw FROM UNNEST(GENERATE_ARRAY(0, 8)) AS rw
)
SELECT
  cs.channel_group,
  cs.cohort_size,
  r.rw AS rel_week,
  COUNT(DISTINCT IF(b.rel_week = r.rw, b.user_pseudo_id, NULL)) AS retained_users,
  ROUND(100 * COUNT(DISTINCT IF(b.rel_week = r.rw, b.user_pseudo_id, NULL)) / cs.cohort_size, 2) AS retention_pct
FROM cohort_sizes cs
CROSS JOIN rel_weeks r
JOIN base b ON b.channel_group = cs.channel_group
GROUP BY 1, 2, 3
ORDER BY 1, 3;


-- =============================================================================
-- Q19. 채널별 W1 / W4 / W8 리텐션 요약 (본문·PPT 표)
--   코호트 = 11월(cohort_week 0~3) 유입 전체
-- =============================================================================
WITH
first_touch AS (
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
      WHEN source = 'shop.googlemerchandisestore.com' THEN 'Self-referral'
      WHEN medium IN ('<Other>', '(data deleted)')     THEN 'Unknown'
      WHEN medium = 'organic'                          THEN 'Organic Search'
      WHEN medium = 'cpc'                              THEN 'Paid Search'
      WHEN medium = 'referral'                         THEN 'Referral'
      WHEN medium = '(none)'                           THEN 'Direct'
      ELSE 'Other'
    END AS channel_group
  FROM first_touch
  WHERE rn = 1
),
cohort AS (
  SELECT
    user_pseudo_id,
    DATE_DIFF(MIN(PARSE_DATE('%Y%m%d', event_date)), DATE '2020-11-01', WEEK(SUNDAY)) AS cohort_week
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'first_visit'
  GROUP BY 1
),
activity AS (
  SELECT DISTINCT
    user_pseudo_id,
    DATE_DIFF(PARSE_DATE('%Y%m%d', event_date), DATE '2020-11-01', WEEK(SUNDAY)) AS activity_week
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'session_start'
),
base AS (
  SELECT
    co.user_pseudo_id,
    ch.channel_group,
    a.activity_week - co.cohort_week AS rel_week
  FROM cohort co
  JOIN channel ch USING (user_pseudo_id)
  LEFT JOIN activity a USING (user_pseudo_id)
  WHERE co.cohort_week BETWEEN 0 AND 3
)
SELECT
  channel_group,
  COUNT(DISTINCT user_pseudo_id) AS cohort_size,
  ROUND(100 * COUNT(DISTINCT IF(rel_week = 1, user_pseudo_id, NULL)) / COUNT(DISTINCT user_pseudo_id), 2) AS w1_pct,
  ROUND(100 * COUNT(DISTINCT IF(rel_week = 4, user_pseudo_id, NULL)) / COUNT(DISTINCT user_pseudo_id), 2) AS w4_pct,
  ROUND(100 * COUNT(DISTINCT IF(rel_week = 8, user_pseudo_id, NULL)) / COUNT(DISTINCT user_pseudo_id), 2) AS w8_pct
FROM base
GROUP BY 1
ORDER BY cohort_size DESC;
