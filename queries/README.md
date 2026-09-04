# 쿼리

실행 환경: BigQuery Console (샌드박스, 월 1TB 한도 내). 데이터셋: `bigquery-public-data.ga4_obfuscated_sample_ecommerce`.
분석 문서(source of truth): 노션 "📊 GA4 유입 채널 성과 분석 — 포트폴리오". 판단 근거·해석은 노션에 있고 여기엔 쿼리만 있다.

| 파일 | 단계 | 쿼리 | 결과 |
|---|---|---|---|
| `phase1_definitions.sql` | 1단계 — 정의 확정 | Q1~Q9 (+ Q3b/c/d, Q5b, Q8b~g) | `../results/phase1/` |
| `phase2_volume.sql` | 2단계 — 채널별 볼륨 | Q10, Q11 | `../results/phase2/` |
| `phase3_funnel.sql` | 3단계 — 채널별 퍼널 | Q13, Q12 | `../results/phase3/` |
| `phase4_value.sql` | 4단계 — 채널별 가치 | Q14, Q15, Q16 | `../results/phase4/` |
| `phase5_cohort.sql` | 5단계 — 코호트·리텐션 | S1, Q17, Q18, Q19 | `../results/phase5/` |

- 한 질문에 쿼리가 둘이면 결과도 둘(`q6_1.json`/`q6_2.json`, `q8_1.json`/`q8_2.json`). Q7·Q9는 별도 실행 없이 기존 결과로 판단 — `phase1_definitions.sql` 하단 주석 참고.
- Phase 2~5의 모든 쿼리는 Phase 1의 `Q5b` first-touch 채널 CTE 패턴을 재사용한다.
- Phase 3은 노션 순서를 따라 Q13(단계 간 포함관계)을 Q12(퍼널 통과율)보다 먼저 둔다.
- `phase5_cohort.sql`은 콘솔 복붙 편의를 위해 쿼리마다 공통 CTE 블록을 반복해 넣었다.

## phase5_cohort.sql 실행 순서
1. `S1` — `total_new_users = 257,314`, `w0_retention_pct = 100` 확인
2. `Q17` — 전체 코호트 히트맵 (long format, 45행) → Tableau 삼각 히트맵
3. `Q18` — 채널 × 상대주차 리텐션 (long format, 54행) → Tableau 라인 6선
4. `Q19` — 채널별 W1/W4/W8 요약 → 본문·PPT 표
