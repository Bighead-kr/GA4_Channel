# 시각화 (Tableau Public)

`chart_specs.md` = 4화면 스펙(마크·인코딩·색·주석). 아래 CSV가 각 화면의 입력.

| 파일 | 화면 | 소스 쿼리 |
|---|---|---|
| `volume.csv` | 1. 채널별 유입 볼륨 | Q10 |
| `quality_dots.csv` | 2. 볼륨은 갈리고 질은 안 갈린다 (점) | Q10·Q12·Q14·Q16·Q19 |
| `metric_spread.csv` | 2. 지표별 채널 편차 폭 (요약 막대) | 위와 동일 |
| `funnel.csv` | 3. 채널별 퍼널 통과율 | Q12 |
| `cohort.csv` | 4. 코호트 리텐션 히트맵 | Q17 (`../results/phase5/`) |

재생성: `results/`의 JSON을 고친 뒤 `viz/build_viz.py` 실행 (스크립트는 저장소 루트에서 실행).

## Tableau Public

https://public.tableau.com/app/profile/.18082116/viz/GA4_17884980209280/1_1
