-- 重新传一次 HAE 后跑这个，看 HAE 到底把 basal/resting energy 发成什么结构

-- 1) 最近一次捕获到的 basal/resting energy 完整原始块（能看到 metric name、units，以及 data[] 里每个采样的字段）
select id, created_at, jsonb_pretty(basal_block) as basal_block_pretty
from public.ingest_debug
order by id desc
limit 3;

-- 2) 把 data[] 里的采样摊平，专门找 qty 接近 1699 的那条，看它的 date / source / 全部字段到底是什么
select
  m ->> 'name'  as metric_name,
  m ->> 'units' as units,
  s as sample_raw,
  s ->> 'qty'    as qty,
  s ->> 'date'   as date_raw,
  s ->> 'source' as source
from public.ingest_debug d
cross join lateral jsonb_array_elements(d.basal_block) as m
cross join lateral jsonb_array_elements(coalesce(m -> 'data', '[]'::jsonb)) as s
where (s ->> 'qty')::numeric > 1000
order by d.id desc
limit 10;
