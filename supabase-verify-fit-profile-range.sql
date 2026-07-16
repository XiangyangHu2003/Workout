-- 只读诊断：看 basal_energy_burned 里，source 含 fit profile 的记录，qty 到底分布在哪些区间
-- 用于确认 qty>=500 这个阈值是不是真的能把"体脂秤 BMR" 和 "被误标的小/中数值" 完全分开
select
  case
    when qty < 5 then '<5 (正常 Apple Watch 分钟级)'
    when qty < 100 then '5~100 (异常，需要关注)'
    when qty < 500 then '100~500 (异常，当前阈值下会被误判成健康指标)'
    else '>=500 (判定为体脂秤 BMR)'
  end as qty_bucket,
  count(*) as n,
  min(qty) as min_qty,
  max(qty) as max_qty,
  min(date_raw) as example_date
from public.body_metrics
where metric = 'basal_energy_burned'
  and source ilike '%fit profile%'
group by 1
order by 1;
