-- basal_energy_burned 分流诊断（全程只读，不修改或删除任何数据）
-- 等重新积累几天数据后执行整个文件。

-- 1) Fit Profile 相关记录的逐行数量级分布。
select
  case
    when qty < 5 then '01 <5'
    when qty < 20 then '02 5~20'
    when qty < 100 then '03 20~100'
    when qty < 500 then '04 100~500 (灰区)'
    else '05 >=500 (BMR候选)'
  end as qty_bucket,
  count(*) as n,
  min(qty) as min_qty,
  max(qty) as max_qty,
  sum(qty) as sum_qty,
  min(date_raw) as first_sample,
  max(date_raw) as last_sample
from public.body_metrics
where metric = 'basal_energy_burned'
  and coalesce(source, '') ilike '%fit profile%'
group by 1
order by 1;

-- 2) 直接列出 20~500 的可疑行。
-- 这些值既不像 1~4 kcal 的分钟级 Watch 样本，也不像 1000~3000 kcal 的完整 BMR；
-- 在确认含义前，不应简单通过降低阈值把它们塞进体脂秤卡片。
select
  id,
  date_raw,
  qty,
  unit,
  source,
  created_at
from public.body_metrics
where metric = 'basal_energy_burned'
  and coalesce(source, '') ilike '%fit profile%'
  and qty >= 20
  and qty < 500
order by date_raw desc, qty desc
limit 500;

-- 3) 检查同一时间戳是否因 source 字符串不同被保存了多次。
-- 当前 dedup_key 包含原始 source；如果同一逻辑样本的 source 表达不稳定，日汇总会重复求和。
select
  user_id,
  date_raw,
  count(*) as row_count,
  count(distinct coalesce(source, '')) as source_variants,
  array_agg(coalesce(source, '<NULL>') order by source) as sources,
  array_agg(qty order by qty) as quantities,
  sum(qty) as duplicated_sum,
  max(qty) as one_sample_qty,
  sum(qty) - max(qty) as possible_overcount
from public.body_metrics
where metric = 'basal_energy_burned'
  and not (coalesce(source, '') ilike '%fit profile%' and qty >= 500)
group by user_id, date_raw
having count(*) > 1
order by possible_overcount desc, date_raw desc
limit 500;

-- 4) 按天比较：正式 Apple 视图当前结果 vs 按 date_raw 只保留一个样本的结果。
-- possible_overcount > 0 就能直接量化 source 变体造成的重复累加。
with apple_rows as (
  select user_id, left(date_raw, 10) as day, date_raw, qty
  from public.body_metrics
  where metric = 'basal_energy_burned'
    and not (coalesce(source, '') ilike '%fit profile%' and qty >= 500)
), per_timestamp as (
  select user_id, day, date_raw, max(qty) as qty
  from apple_rows
  group by user_id, day, date_raw
), deduped_daily as (
  select user_id, day, sum(qty) as deduped_qty
  from per_timestamp
  group by user_id, day
), current_daily as (
  select user_id, day, sum(qty) as current_qty, count(*) as current_n
  from apple_rows
  group by user_id, day
)
select
  c.day,
  c.current_qty,
  d.deduped_qty,
  c.current_qty - d.deduped_qty as possible_overcount,
  c.current_n
from current_daily c
join deduped_daily d using (user_id, day)
order by c.day desc;

-- 5) 确认线上真实视图定义，防止 SQL 文件与已部署对象不一致。
select pg_get_viewdef('public.body_metrics_apple_basal_daily'::regclass, true)
  as apple_basal_daily_definition;
select pg_get_viewdef('public.body_metrics_scale_bmr_daily'::regclass, true)
  as scale_bmr_daily_definition;

-- 6) 检查临时调试表是否仍存在（只返回 true/false，不删除）。
select to_regclass('public.ingest_debug') is not null as ingest_debug_still_exists;

-- 7) 确认线上 ingest_watch 函数本身是否仍包含调试写入。
select
  position('ingest_debug' in pg_get_functiondef('public.ingest_watch(jsonb)'::regprocedure)) > 0
    as ingest_watch_still_writes_debug;
