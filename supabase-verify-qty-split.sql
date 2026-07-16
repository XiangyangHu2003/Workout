-- 只读验证：必须先逐行分类，再汇总。
-- 不能按 day/source 分组后用 max(qty) 分类；那会把同组的小额 Watch 样本一起误标成 BMR。
with classified as (
  select
    left(date_raw, 10) as day,
    source,
    qty,
    case
      when coalesce(source, '') ilike '%fit profile%' and qty >= 500
        then 'scale_bmr'
      else 'apple_health'
    end as bucket
  from public.body_metrics
  where metric = 'basal_energy_burned'
)
select
  day,
  bucket,
  source,
  count(*) as n,
  min(qty) as min_qty,
  max(qty) as max_qty,
  sum(qty) as sum_qty
from classified
group by day, bucket, source
order by day desc, bucket, source;

select 'scale_bmr' as view_name, day, qty, n
from public.body_metrics_scale_bmr_daily
order by day desc
limit 10;

select 'apple_basal' as view_name, day, qty, n
from public.body_metrics_apple_basal_daily
order by day desc
limit 10;

