-- 只读诊断：确认 2026-07-07 到底有没有体重（weight_body_mass / body_mass）读数
select metric, date_raw, qty, unit, source, created_at
from public.body_metrics
where metric in ('weight_body_mass','body_mass')
order by date_raw desc
limit 20;

-- 补充：Fit Profile 那次 BMR 读数（2026-07-07 晚上 7 点左右）附近，同一时间戳还导出了哪些指标
-- 正常情况下体重秤一次称重会把体重/体脂/BMI/BMR等一起写入，应该能在这里看到 weight_body_mass
select metric, date_raw, qty, unit, source
from public.body_metrics
where source ilike '%fit profile%'
  and left(date_raw,10) = '2026-07-07'
order by date_raw;
