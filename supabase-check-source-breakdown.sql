-- 只读诊断：2026-07-07 basal_energy_burned 按 source 精确分组，
-- 并显示每个 source 是否满足我们两个视图各自的判断条件（true/false 一眼看出问题出在哪一步）
select
  source,
  length(source) as source_len,
  count(*) as n,
  sum(qty) as sum_qty,
  avg(qty) as avg_qty,
  (coalesce(source,'') !~* 'apple watch') as not_contains_apple_watch,
  (source ~* 'fit profile') as contains_fit_profile
from public.body_metrics
where metric = 'basal_energy_burned'
  and left(date_raw,10) = '2026-07-07'
group by source
order by n desc;
