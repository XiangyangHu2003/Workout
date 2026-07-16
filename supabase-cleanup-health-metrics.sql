-- 练迹：Health Metrics / 体脂秤数据清理 —— 只读检查 + 预览脚本
-- 用法：在 Supabase Dashboard > SQL Editor 里【分段】执行，每段先看结果再往下走。
-- 第 6 段 DELETE 默认不要执行，等你确认预览结果无误后再手动跑。

-- ============================================================
-- 1) 相关表名和字段（schema 自检）
-- ============================================================
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name in ('watch_workouts', 'body_metrics', 'body_metrics_daily', 'ingest_tokens')
order by table_name, ordinal_position;

-- 说明（来自代码里的 supabase-watch.sql，非本次查询结果）：
--   watch_workouts: id, user_id, source, payload(jsonb), created_at, dedup_key  -> 训练数据
--   body_metrics:   id, user_id, metric, date_raw, qty, unit, source, created_at, dedup_key -> 健康指标/体脂秤
--   没有名为 source_type / ingest_source 的字段，实际列名是 source（两张表都有，含义不同）。

-- ============================================================
-- 2) 各表行数
-- ============================================================
select 'watch_workouts' as table_name, count(*) as row_count from public.watch_workouts
union all
select 'body_metrics', count(*) from public.body_metrics
union all
select 'ingest_tokens', count(*) from public.ingest_tokens;

-- ============================================================
-- 3) distinct source 值（watch_workouts.source / body_metrics.source / body_metrics.metric）
-- ============================================================
-- watch_workouts.source: 应该只有 auto / manual / auto-raw 三种
select source, count(*) as n
from public.watch_workouts
group by source
order by n desc;

-- body_metrics.source: HAE 上报的设备/数据来源名（如 Fit Profile、Apple Watch 等）
select source, count(*) as n
from public.body_metrics
group by source
order by n desc;

-- body_metrics.metric: 真正决定"是不是体脂秤/健康指标"的字段，混有日常活动指标（步数/心率等）
select metric, count(*) as n
from public.body_metrics
group by metric
order by n desc;

-- ============================================================
-- 4) 预览最近 20 条：区分 Health Metrics vs Workouts
-- ============================================================
-- 4a) watch_workouts 最近 20 条 raw payload，按关键词打标（重点看 source='auto-raw' 的行）
select
  id,
  source,
  created_at,
  payload ->> 'name'               as workout_name,
  payload ->> 'workoutActivityType' as workout_activity_type,
  payload ->> 'start'              as start_raw,
  payload ->> 'startDate'          as start_date_raw,
  (payload::text ~* '(body[ _]?mass|body[ _]?fat|bmi|lean[ _]?body[ _]?mass|muscle[ _]?mass|basal[ _]?metabolic[ _]?rate|visceral[ _]?fat|fit[ _]?profile)') as looks_like_health_metric,
  (payload::text ~* '(workoutactivitytype|activeenergy|startdate|enddate)') as looks_like_workout,
  left(payload::text, 300) as payload_preview
from public.watch_workouts
order by created_at desc
limit 20;

-- 4b) body_metrics 最近 20 条（本来就是结构化的，不是 raw json，直接看字段即可）
select id, metric, date_raw, qty, unit, source, created_at
from public.body_metrics
order by created_at desc
limit 20;

-- ============================================================
-- 5) 预览：将被 DELETE 的数据范围 + 数量 + 最近几条
-- ============================================================
-- 关键词集合（Health Metrics / 体脂秤）：
--   Body Mass, Body Fat, BMI, Lean Body Mass, Muscle Mass,
--   Basal Metabolic Rate, Visceral Fat, Fit Profile
-- 只匹配 metric 名/payload 文本命中关键词的行；不命中（如 step_count、resting_heart_rate、
-- workoutActivityType 等）一律不动，避免误删训练/日常指标数据。

-- 5a) body_metrics：将删除的行数
select count(*) as will_delete_body_metrics
from public.body_metrics
where metric ~* '(body[ _]?mass|body[ _]?fat|bmi|lean[ _]?body[ _]?mass|muscle[ _]?mass|basal[ _]?metabolic[ _]?rate|visceral[ _]?fat|fit[ _]?profile)';

-- 5b) body_metrics：不会被删除、但也不确定是什么的 metric 种类（人工确认用，不在关键词命中范围内的全部保留）
select metric, count(*) as n
from public.body_metrics
where metric !~* '(body[ _]?mass|body[ _]?fat|bmi|lean[ _]?body[ _]?mass|muscle[ _]?mass|basal[ _]?metabolic[ _]?rate|visceral[ _]?fat|fit[ _]?profile)'
group by metric
order by n desc;

-- 5c) body_metrics：将删除的最近 20 条长什么样
select id, metric, date_raw, qty, unit, source, created_at
from public.body_metrics
where metric ~* '(body[ _]?mass|body[ _]?fat|bmi|lean[ _]?body[ _]?mass|muscle[ _]?mass|basal[ _]?metabolic[ _]?rate|visceral[ _]?fat|fit[ _]?profile)'
order by created_at desc
limit 20;

-- 5d) watch_workouts：误存的 auto-raw 健康指标行（命中健康关键词 且 不含任何训练关键词，才算数）
select count(*) as will_delete_watch_workouts_misfiled
from public.watch_workouts
where source = 'auto-raw'
  and payload::text ~* '(body[ _]?mass|body[ _]?fat|bmi|lean[ _]?body[ _]?mass|muscle[ _]?mass|basal[ _]?metabolic[ _]?rate|visceral[ _]?fat|fit[ _]?profile)'
  and payload::text !~* '(workoutactivitytype|activeenergy|startdate|enddate)';

-- 5e) watch_workouts：将删除的最近 20 条长什么样
select id, source, created_at, left(payload::text, 300) as payload_preview
from public.watch_workouts
where source = 'auto-raw'
  and payload::text ~* '(body[ _]?mass|body[ _]?fat|bmi|lean[ _]?body[ _]?mass|muscle[ _]?mass|basal[ _]?metabolic[ _]?rate|visceral[ _]?fat|fit[ _]?profile)'
  and payload::text !~* '(workoutactivitytype|activeenergy|startdate|enddate)'
order by created_at desc
limit 20;

-- ============================================================
-- 6) DELETE（先不要执行！确认 5a/5d 的数量和 5c/5e 的样本都符合预期后，再手动执行下面这段）
-- ============================================================
-- begin;
--
-- delete from public.body_metrics
-- where metric ~* '(body[ _]?mass|body[ _]?fat|bmi|lean[ _]?body[ _]?mass|muscle[ _]?mass|basal[ _]?metabolic[ _]?rate|visceral[ _]?fat|fit[ _]?profile)';
--
-- delete from public.watch_workouts
-- where source = 'auto-raw'
--   and payload::text ~* '(body[ _]?mass|body[ _]?fat|bmi|lean[ _]?body[ _]?mass|muscle[ _]?mass|basal[ _]?metabolic[ _]?rate|visceral[ _]?fat|fit[ _]?profile)'
--   and payload::text !~* '(workoutactivitytype|activeenergy|startdate|enddate)';
--
-- commit;
