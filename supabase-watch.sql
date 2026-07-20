-- 练迹：Apple Watch 数据接入（Health Auto Export → Supabase）
-- 在 Supabase Dashboard > SQL Editor > New query 中执行整个文件。
-- 设计：后端只负责“存原始 JSON”，字段解析放在网页端，方便日后无损调整。

-- 清理旧环境中额外安装的公开 SECURITY DEFINER 事件触发器。
drop event trigger if exists ensure_rls;
drop function if exists public.rls_auto_enable();

-- 1) 手表训练原始数据表（每条训练一行，payload 存 Health Auto Export 的原始 JSON）
create table if not exists public.watch_workouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source text not null default 'auto',        -- auto=自动同步  manual=手动导入
  payload jsonb not null,                      -- 原始训练 JSON，不做破坏性转换
  created_at timestamptz not null default now(),
  -- 去重键：同一 start+name 视为同一次训练（HAE 会批量重发历史，需防重）
  dedup_key text generated always as (
    coalesce(payload->>'start', payload->>'startDate','') || '|' || coalesce(payload->>'name','')
  ) stored
);
alter table public.watch_workouts enable row level security;
revoke all on table public.watch_workouts from anon;
grant select, insert, delete on table public.watch_workouts to authenticated;

drop policy if exists "read own watch" on public.watch_workouts;
create policy "read own watch" on public.watch_workouts
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "insert own watch" on public.watch_workouts;
create policy "insert own watch" on public.watch_workouts
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists "delete own watch" on public.watch_workouts;
create policy "delete own watch" on public.watch_workouts
  for delete to authenticated using ((select auth.uid()) = user_id);

create index if not exists watch_workouts_user_created
  on public.watch_workouts(user_id, created_at desc);
-- 唯一索引：同一账号下同一次训练只保留一条，接口用 on conflict 跳过重复
create unique index if not exists watch_workouts_user_dedup
  on public.watch_workouts(user_id, dedup_key);

-- 2) 设备同步令牌：浏览器只展示一次原始令牌，数据库仅保存 SHA-256 哈希。
create extension if not exists pgcrypto with schema extensions;
create table if not exists public.ingest_tokens (
  token_hash text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  label text,
  created_at timestamptz not null default now()
);

-- 从旧版明文 token 结构迁移。仅在旧列仍存在时清空一次旧令牌，重复执行不会删除新令牌。
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'ingest_tokens' and column_name = 'token'
  ) then
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'ingest_tokens' and column_name = 'token_hash'
    ) then
      alter table public.ingest_tokens add column token_hash text;
    end if;
    delete from public.ingest_tokens;
    alter table public.ingest_tokens drop constraint if exists ingest_tokens_pkey;
    alter table public.ingest_tokens drop column token;
    alter table public.ingest_tokens alter column token_hash set not null;
    alter table public.ingest_tokens add primary key (token_hash);
  end if;
end
$$;
alter table public.ingest_tokens enable row level security;
revoke all on table public.ingest_tokens from anon;
grant select, insert, delete on table public.ingest_tokens to authenticated;
create index if not exists ingest_tokens_user_id_idx on public.ingest_tokens(user_id);

drop policy if exists "own tokens" on public.ingest_tokens;
create policy "own tokens" on public.ingest_tokens
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- 3) 接收接口：Health Auto Export 以 anon key + 自定义令牌头 POST 到这里
--    调用方式（Health Auto Export 里配置）：
--      URL:  https://<你的项目>.supabase.co/rest/v1/rpc/ingest_watch
--      Headers:
--        apikey: <你的 publishable / anon key>
--        x-ingest-token: <在练迹里生成的同步令牌>
--        Content-Type: application/json
--    说明：函数参数名为 data，正好对应 HAE 请求体顶层的 "data" 键，
--          因此无需 Prefer 头（PostgREST 默认把顶层键映射到同名参数）。
-- 2b) 体脂秤 / 身体成分指标（Health Metrics automation → data.metrics[]）
create table if not exists public.body_metrics (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  metric text not null,            -- HAE 指标名，如 weight_body_mass / body_fat_percentage
  date_raw text not null,          -- 采样时间原始字符串，前端解析
  qty numeric,
  unit text,
  source text,
  created_at timestamptz not null default now(),
  -- 去重键必须带上 source：同一分钟内 Apple Watch 分钟级数据和 Fit Profile 体脂秤数据可能落在同一个
  -- date_raw 时间戳上，如果去重键只看 metric+date_raw，先到的会挡住后到的（on conflict do nothing
  -- 静默丢弃，不报错），导致晚到的那条真实数据永远进不了库。
  dedup_key text generated always as (metric || '|' || date_raw || '|' || coalesce(source, '')) stored
);

-- 兼容早期版本：旧去重键只有 metric + date_raw，会让同一时刻、不同来源的数据互相覆盖。
-- 仅在检测到旧定义时迁移；重复执行本文件不会反复重建字段。
do $$
declare
  dedup_expression text;
begin
  select pg_get_expr(ad.adbin, ad.adrelid)
    into dedup_expression
  from pg_attribute a
  join pg_attrdef ad
    on ad.adrelid = a.attrelid and ad.adnum = a.attnum
  where a.attrelid = 'public.body_metrics'::regclass
    and a.attname = 'dedup_key';

  if dedup_expression is not null
     and dedup_expression not ilike '%source%' then
    drop index if exists public.body_metrics_user_dedup;
    alter table public.body_metrics drop column dedup_key;
    alter table public.body_metrics add column dedup_key text generated always as (
      metric || '|' || date_raw || '|' || coalesce(source, '')
    ) stored;
  end if;
end
$$;
alter table public.body_metrics enable row level security;
revoke all on table public.body_metrics from anon;
grant select, insert, delete on table public.body_metrics to authenticated;
drop policy if exists "read own body" on public.body_metrics;
create policy "read own body" on public.body_metrics for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "insert own body" on public.body_metrics;
create policy "insert own body" on public.body_metrics for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists "delete own body" on public.body_metrics;
create policy "delete own body" on public.body_metrics for delete to authenticated using ((select auth.uid()) = user_id);
create unique index if not exists body_metrics_user_dedup on public.body_metrics(user_id, dedup_key);
create index if not exists body_metrics_user_date on public.body_metrics(user_id, date_raw desc);

-- 2c) 按天聚合视图：原始数据是每分钟一条、量极大，前端只读这个聚合结果
--     累计类指标(步数/能量/时间/距离)当天求和，其余取平均；day 取 date_raw 前 10 位(YYYY-MM-DD)
create or replace view public.body_metrics_daily
with (security_invoker = on) as
select
  user_id,
  metric,
  left(date_raw, 10) as day,
  case when metric in ('step_count','active_energy','basal_energy_burned','apple_exercise_time','apple_stand_time','apple_stand_hour','flights_climbed','walking_running_distance','handwashing')
       then sum(qty) else avg(qty) end as qty,
  max(unit) as unit,
  count(*)::int as n
from public.body_metrics
group by user_id, metric, left(date_raw, 10);
grant select on public.body_metrics_daily to authenticated;

-- 2d) basal_energy_burned 按天聚合视图（按来源拆成两份）：
--     该 metric 同时混有 Apple Watch 分钟级数据（一天几百条）和 Fit Profile 体脂秤算出的 BMR（一天一条）。
--     body_metrics_daily 会把两者按天加在一起，前端也没法只按 metric=eq.basal_energy_burned 拉原始行做区分——
--     Apple Watch 的分钟级数据量太大，几个月历史就会超过前端 20000 行的读取上限，导致早期日期被截断。
--     所以直接在数据库里按来源分别聚合成两张“天”粒度的小表，前端只读聚合结果，不再读原始行。
--     实测 source 有三种真实形态：
--       1) "XX的Apple Watch"              → Apple Watch 分钟级静息能量（一天几百~几千条，每条约 1~4kcal）
--       2) "Fit Profile"                  → 体脂秤算出的 BMR（每条约 1699kcal）
--       3) "XX的Apple Watch|Fit Profile"  → 混合来源：既可能是 Apple Watch 分钟级数据（每条约 1~2kcal），
--                                            也可能是体脂秤 BMR（约 1699kcal）——光看 source 字符串区分不了！
--     所以【不能只靠 source 字符串判断】。真正可靠的区分是【数值量级】：
--       - Apple Watch 分钟级静息能量：每条 1~4 kcal（物理上不可能单条上百）
--       - 体脂秤 BMR：单条约 1000~3000 kcal
--     判定规则：source 含 "fit profile" 且单条 qty >= 500，才算体脂秤 BMR；其余全部算 Apple Watch。
--     （source 用 ILIKE '%fit profile%' 做包含匹配，避开设备名里中英文之间非普通空格导致的正则/短语匹配失败问题。）
create or replace view public.body_metrics_apple_basal_daily
with (security_invoker = on) as
select
  user_id,
  left(date_raw, 10) as day,
  sum(qty) as qty,
  max(unit) as unit,
  count(*)::int as n
from public.body_metrics
where metric = 'basal_energy_burned'
  and not (coalesce(source, '') ilike '%fit profile%' and qty >= 500)
group by user_id, left(date_raw, 10);
grant select on public.body_metrics_apple_basal_daily to authenticated;

create or replace view public.body_metrics_scale_bmr_daily
with (security_invoker = on) as
select
  user_id,
  left(date_raw, 10) as day,
  avg(qty) as qty,
  max(unit) as unit,
  count(*)::int as n
from public.body_metrics
where metric = 'basal_energy_burned'
  and coalesce(source, '') ilike '%fit profile%'
  and qty >= 500
group by user_id, left(date_raw, 10);
grant select on public.body_metrics_scale_bmr_daily to authenticated;

drop function if exists public.ingest_watch(jsonb);
create or replace function public.ingest_watch(data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  hdr_token text;
  uid uuid;
  wk jsonb;
  m jsonb;
  s jsonb;
  workouts_data jsonb;
  metrics_data jsonb;
  samples_data jsonb;
  n int := 0;
begin
  hdr_token := (current_setting('request.headers', true)::jsonb) ->> 'x-ingest-token';
  if hdr_token is null or length(hdr_token) < 32 then
    raise exception 'missing x-ingest-token header';
  end if;

  select user_id into uid
  from public.ingest_tokens
  where token_hash = encode(extensions.digest(hdr_token, 'sha256'), 'hex');
  if uid is null then
    raise exception 'invalid ingest token';
  end if;

  if data is null or jsonb_typeof(data) <> 'object' then
    raise exception 'request data must be a JSON object';
  end if;
  if pg_column_size(data) > 10485760 then
    raise exception 'request data exceeds 10 MB';
  end if;

  workouts_data := coalesce(data -> 'workouts', data #> '{data,workouts}', '[]'::jsonb);
  metrics_data := coalesce(data -> 'metrics', '[]'::jsonb);
  if jsonb_typeof(workouts_data) <> 'array' or jsonb_typeof(metrics_data) <> 'array' then
    raise exception 'workouts and metrics must be arrays';
  end if;
  if jsonb_array_length(workouts_data) > 500 or jsonb_array_length(metrics_data) > 200 then
    raise exception 'request contains too many workouts or metrics';
  end if;

  -- data 已是请求体 "data" 键的值；兼容 {workouts:[]} 与 {data:{workouts:[]}} 两种结构
  for wk in
    select value from jsonb_array_elements(workouts_data) as t(value)
  loop
    insert into public.watch_workouts(user_id, payload, source)
    values (uid, wk, 'auto')
    on conflict (user_id, dedup_key) do nothing;
    n := n + 1;
  end loop;

  -- Health Metrics：data.metrics[] → 每个指标的 data[] 采样（体脂秤/身体成分）
  for m in
    select value from jsonb_array_elements(metrics_data) as t(value)
  loop
    if jsonb_typeof(m) <> 'object' then
      raise exception 'each metric must be an object';
    end if;
    samples_data := coalesce(m -> 'data', '[]'::jsonb);
    if jsonb_typeof(samples_data) <> 'array' or jsonb_array_length(samples_data) > 20000 then
      raise exception 'metric samples must be an array with at most 20000 items';
    end if;
    for s in
      select value from jsonb_array_elements(samples_data) as t2(value)
    loop
      if n >= 50000 then
        raise exception 'request contains more than 50000 total items';
      end if;
      if (s ->> 'qty') is not null and (s ->> 'date') is not null then
        insert into public.body_metrics(user_id, metric, date_raw, qty, unit, source)
        values (uid, m ->> 'name', s ->> 'date', nullif(s ->> 'qty','')::numeric, m ->> 'units', s ->> 'source')
        on conflict (user_id, dedup_key) do nothing;
        n := n + 1;
      end if;
    end loop;
  end loop;

  -- 都没有则原样存一条，便于排查真实字段结构
  if n = 0 then
    insert into public.watch_workouts(user_id, payload, source)
    values (uid, data, 'auto-raw')
    on conflict (user_id, dedup_key) do nothing;
    n := 1;
  end if;

  return jsonb_build_object('inserted', n);
end;
$$;

revoke all on function public.ingest_watch(jsonb) from public;
grant execute on function public.ingest_watch(jsonb) to anon, authenticated;
