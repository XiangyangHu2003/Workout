-- 只读诊断：对比"今天"active_energy 和 basal_energy_burned(排除 Fit Profile)最近一条样本的写入时间
-- 如果 basal_energy_burned 的 max(date_raw)/max(created_at) 明显早于 active_energy，
-- 就能确认是 HealthKit/Health Auto Export 那边基础能量样本本来就写得稀疏、还没同步新的，
-- 不是这个 App 前端或数据库视图的问题。
select
  metric,
  count(*) as rows_today,
  max(date_raw) as latest_sample_time,
  max(created_at) as latest_synced_at
from public.body_metrics
where metric in ('active_energy','basal_energy_burned')
  and left(date_raw,10) = to_char(now(), 'YYYY-MM-DD')  -- 按需要改成你本地今天的日期，例如 '2026-07-08'
  and (metric != 'basal_energy_burned' or coalesce(source,'') !~* 'fit profile')
group by metric;

-- 如果想看 basal_energy_burned 今天最近 10 条原始样本的具体时间点和来源：
select date_raw, qty, unit, source, created_at
from public.body_metrics
where metric = 'basal_energy_burned'
  and left(date_raw,10) = to_char(now(), 'YYYY-MM-DD')  -- 同上，按需改成你本地今天日期
order by date_raw desc
limit 10;
