-- 只读诊断：精确查找 source 严格等于 'Fit Profile'（不含 Apple Watch）的 basal_energy_burned 记录，
-- 不做任何日期筛选，直接看这些记录现在是否还存在、date_raw 具体是什么
select metric, date_raw, qty, unit, source, created_at
from public.body_metrics
where metric = 'basal_energy_burned'
  and source = 'Fit Profile';
