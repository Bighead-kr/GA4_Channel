# GA4 유입 채널 성과 분석

Google Merchandise Store의 GA4 공개 데이터로 **"어떤 유입 채널이 트래픽을 데려오고, 어떤 채널이 실제로 사는 유저·남는 유저를 데려오는가"** 를 분석한 포트폴리오 프로젝트.

- **데이터:** `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` (2020-11-01 ~ 2021-01-31, 92일 / 이벤트 429만 · 유저 27만 · 세션 36만)
- **실행 환경:** BigQuery Console (샌드박스, 월 1TB 무료 한도 내)
- **분석 문서 (source of truth):** 노션 "📊 GA4 유입 채널 성과 분석 — 포트폴리오" — 질문·판단 근거·해석 전문
- 이 저장소는 그 문서의 **쿼리와 결과 데이터**만 정리한 것

## 핵심 결론

유입 채널은 볼륨이 최대 7배까지 갈리지만(Organic 37.7% vs Paid 5.3%), **진입률·퍼널 통과율·구매 전환율·객단가·8주 리텐션 어느 지표에서도 채널 간 유저 질 차이가 없다.** 따라서 예산을 채널 간에 재배분해 얻을 것은 없고, 지렛대는 채널이 아니라 전 채널 공통의 퍼널 이탈 구간과 5% 수준의 주간 재방문율이다.

> 당초 결론은 "볼륨 큰 채널과 가치 큰 채널이 어긋난다 → 예산을 옮겨라"였으나, 데이터가 이를 허락하지 않아(식별 가능한 유료 채널이 `google/cpc` 하나뿐, 채널 질 균질) 결론을 재정의했다. 이 과정 자체가 분석의 일부다.

## 구조

```
queries/
  phase1_definitions.sql   Q1~Q9  — 세션·신규유저·채널귀속·구매 정의 확정 (+ 분기쿼리)
  phase2_volume.sql        Q10~Q11 — 채널별 볼륨, 계절성 교란 점검
  phase3_funnel.sql        Q13,Q12 — 단계 간 포함관계 → 채널×5단계 퍼널 통과율
  phase4_value.sql         Q14~Q16 — 전환율·객단가·ARPU, 구성효과·견고성 점검
  phase5_cohort.sql        S1,Q17~Q19 — 코호트·리텐션 (히트맵 + 채널 곡선)
results/
  phase1/ ... phase5/       각 쿼리의 실행 결과 (JSON / CSV)
```

## 확정된 정의 (Phase 1)

| 정의 | 확정 내용 |
|---|---|
| 세션 | `user_pseudo_id` × `ga_session_id` (360,129개, 결측 0) |
| 신규 유저 | 관측 기간 내 `first_visit` 보유 `user_pseudo_id` (257,314명, 95.2%) |
| 채널 귀속 | `traffic_source`를 유저별 최초 이벤트로 고정(first-touch). `medium` 주축 6그룹: Organic Search / Paid Search / Referral / Direct / Self-referral / Unknown |
| 구매 | `purchase` 이벤트. 유효 `transaction_id`는 첫 발화만, `(not set)`·NULL은 유지 (5,357건 / $339,457) |

## 재현 방법

1. [BigQuery Console](https://console.cloud.google.com/bigquery) 접속 (구글 계정, 결제 계정 불필요 — 샌드박스)
2. `queries/*.sql`의 각 쿼리를 순서대로 실행. 모든 쿼리에 `_TABLE_SUFFIX BETWEEN '20201101' AND '20210131'` 조건이 들어 있다.
3. Phase 5는 `S1`(검증) → `Q17` → `Q18` → `Q19` 순서.
4. 결과를 `results/`의 대응 파일과 대조.
