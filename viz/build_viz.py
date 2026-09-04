#!/usr/bin/env python3
"""viz/ CSV 재생성. 저장소 루트에서 실행: python3 viz/build_viz.py

파일명은 공통 접두사를 피한다 (Tableau가 접두사 같은 CSV를 자동 유니온함).
"""
import json, csv, shutil

q10 = {d['channel_group']: d for d in json.load(open('results/phase2/q10.json'))}
q12 = {d['channel_group']: d for d in json.load(open('results/phase3/q12.json'))}
q14 = {d['channel_group']: d for d in json.load(open('results/phase4/q14.json'))}
q16 = {d['channel_group']: d for d in json.load(open('results/phase4/q16.json'))}
q19 = {d['channel_group']: d for d in json.load(open('results/phase5/q19_channel_summary.json'))}

order = ['Organic Search', 'Direct', 'Unknown', 'Referral', 'Self-referral', 'Paid Search']
spendable = {'Organic Search', 'Paid Search', 'Referral'}

# screen 1
with open('viz/volume.csv', 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['channel', 'channel_order', 'users', 'user_pct', 'is_spendable'])
    for i, c in enumerate(order):
        w.writerow([c, i + 1, q10[c]['users'], q10[c]['user_pct'], int(c in spendable)])

# screen 2
metrics = [
    ('users', '유입 유저수', lambda c: float(q10[c]['users'])),
    ('view_item_rate', 'view_item 도달률(%)', lambda c: float(q10[c]['view_item_rate'])),
    ('view_to_purchase', '퍼널 전환율(%)', lambda c: float(q12[c]['view_to_purchase'])),
    ('median_order', '주문금액 중앙값($)', lambda c: float(q16[c]['median'])),
    ('arpu', 'ARPU($)', lambda c: float(q14[c]['arpu'])),
    ('w1_retention', 'W1 리텐션(%)', lambda c: float(q19[c]['w1_pct'])),
]
with open('viz/quality_dots.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['metric', 'metric_order', 'metric_label', 'channel', 'channel_order',
                'raw_value', 'mean_value', 'pct_dev_from_mean', 'is_spendable'])
    for mi, (mkey, mlabel, fn) in enumerate(metrics):
        vals = [fn(c) for c in order]; mean = sum(vals) / len(vals)
        for ci, c in enumerate(order):
            v = fn(c)
            w.writerow([mkey, mi + 1, mlabel, c, ci + 1, round(v, 2), round(mean, 2),
                        round((v - mean) / mean * 100, 1), int(c in spendable)])

def spread(cs, fn):
    vals = [fn(c) for c in cs]; m = sum(vals) / len(vals)
    devs = [(v - m) / m * 100 for v in vals]
    return round(max(devs) - min(devs), 1)

with open('viz/metric_spread.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['metric', 'metric_order', 'metric_label', 'spread_all6_pp', 'spread_spendable3_pp'])
    for mi, (mkey, mlabel, fn) in enumerate(metrics):
        w.writerow([mkey, mi + 1, mlabel, spread(order, fn),
                    spread(['Organic Search', 'Referral', 'Paid Search'], fn)])

# screen 3
steps = [('view_item', 1), ('add_to_cart', 2), ('begin_checkout', 3),
         ('add_payment_info', 4), ('purchase', 5)]
with open('viz/funnel.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['channel', 'channel_order', 'step', 'step_order', 'users_at_step',
                'pct_of_view_item', 'step_to_step_pct', 'is_spendable'])
    for ci, c in enumerate(order):
        vi = float(q12[c]['view_item']); prev = None
        for skey, so in steps:
            n = float(q12[c][skey])
            w.writerow([c, ci + 1, skey, so, int(n), round(n / vi * 100, 1),
                        round(n / prev * 100, 1) if prev else 100.0, int(c in spendable)])
            prev = n

# screen 4
shutil.copy('results/phase5/q17_cohort_retention.csv', 'viz/cohort.csv')
print('viz/ regenerated')
