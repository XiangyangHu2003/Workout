-- ============================================================
-- 诊断1：确认 dedup_key 迁移是否真的生效了（最关键）
--   如果 generation_expression 里【没有】出现 source，说明 supabase-fix-dedup-key.sql 没跑成功，
--   那你重新传 7/7 数据时碰撞会再次发生、BMR 再次被静默丢弃 —— 必须先把迁移跑成功。
-- ============================================================
select column_name, generation_expression
from information_schema.columns
where table_schema = 'public'
  and table_name = 'body_metrics'
  and column_name = 'dedup_key';

-- ============================================================
-- 诊断2：全表范围内，basal_energy_burned 里有没有任何"体脂秤 BMR 量级"（qty>1000）的记录？
--   —— 不限日期。如果重新传成功、且迁移生效，这里应该能看到 Fit Profile 的 ~1699 记录。
--   如果还是 0 行，说明这些大数值记录根本没被重新写进来。
-- ============================================================
select date_raw, qty, unit, source, created_at
from public.body_metrics
where metric = 'basal_energy_burned'
  and qty > 1000
order by created_at desc
limit 20;

-- ============================================================
-- 诊断3：确认"重新传"到底有没有把新数据写进库
--   看 body_metrics 表里最新的 created_at，以及最近这批数据覆盖到哪些天。
--   如果 max(created_at) 还停在几天前，说明这次重新传根本没落库（HAE 那边没成功发出）。
-- ============================================================
select
  max(created_at) as latest_write,
  min(date_raw) as earliest_sample,
  max(date_raw) as latest_sample,
  count(*) as total_rows
from public.body_metrics;

-- ============================================================
-- 诊断4：Fit Profile 来源的所有记录（不限指标、不限日期），确认体脂秤数据本身还在不在、最新一次是什么时候
-- ============================================================
select metric, date_raw, qty, unit, source, created_at
from public.body_metrics
where source ilike '%fit profile%'
  and source not ilike '%apple%'
order by created_at desc
limit 30;
