-- 只读诊断：确认当前部署在 Supabase 里的视图定义到底是什么，以及分类结果是否符合预期

-- 1) 打印两个视图当前的真实定义（看是不是我给的那版 SQL，还是跑了旧版本/漏了部分）
select pg_get_viewdef('public.body_metrics_apple_basal_daily'::regclass, true) as apple_basal_daily_def;
select pg_get_viewdef('public.body_metrics_scale_bmr_daily'::regclass, true) as scale_bmr_daily_def;

-- 2) 直接对 2026-07-07 的 basal_energy_burned 原始数据，按我期望的判定规则分类，
--    看"混合 source"那 262 条到底被分到了哪一类
select
  source,
  count(*) as n,
  sum(qty) as sum_qty,
  case
    when coalesce(source,'') ilike '%fit profile%' and qty >= 500 then 'scale_bmr（体脂秤）'
    else 'apple_health（健康指标）'
  end as expected_bucket
from public.body_metrics
where metric = 'basal_energy_burned'
  and left(date_raw,10) = '2026-07-07'
group by source;

-- 3) 两个视图现在各自对 2026-07-07 实际返回的值
select * from public.body_metrics_scale_bmr_daily where day = '2026-07-07';
select * from public.body_metrics_apple_basal_daily where day = '2026-07-07';
