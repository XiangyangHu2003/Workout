-- 只读验证：用只匹配 "apple" 单词（不依赖 apple 和 watch 之间的分隔符）重新分组
select
  source,
  count(*) as n,
  sum(qty) as sum_qty,
  (coalesce(source,'') not ilike '%apple%') as not_contains_apple,
  (source ilike '%fit profile%') as contains_fit_profile
from public.body_metrics
where metric = 'basal_energy_burned'
  and left(date_raw,10) = '2026-07-07'
group by source
order by n desc;
