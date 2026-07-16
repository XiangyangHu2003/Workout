-- 只读验证：用 ILIKE 重新跑一遍同样的分组，确认能正确识别出"胡项洋的Apple Watch"里的 Apple Watch
select
  source,
  count(*) as n,
  sum(qty) as sum_qty,
  (coalesce(source,'') not ilike '%apple watch%') as not_contains_apple_watch,
  (source ilike '%fit profile%') as contains_fit_profile
from public.body_metrics
where metric = 'basal_energy_burned'
  and left(date_raw,10) = '2026-07-07'
group by source
order by n desc;
