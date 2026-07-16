-- ============================================================
-- 临时诊断：捕获 HAE 发来的原始 payload，专门看 basal_energy_burned 的真实结构
-- 这只是【新增】一张调试表 + 给 ingest_watch 开头加一行日志，完全保留原有入库逻辑，不改任何已有数据。
-- 用完可以直接把 ingest_debug 表删掉、把函数换回 supabase-watch.sql 里的原版。
-- ============================================================

-- 1) 调试表：存最近几次收到的原始 metrics 里 basal_energy_burned 那一块
create table if not exists public.ingest_debug (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  basal_block jsonb
);

-- 2) 在 ingest_watch 里，解析 metrics 之前，把 basal_energy_burned 那一段原样存进 ingest_debug
--    （只加了标注 <<< DEBUG >>> 的那一段，其余逻辑和 supabase-watch.sql 里的原版完全一致）
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
  n int := 0;
begin
  hdr_token := (current_setting('request.headers', true)::jsonb) ->> 'x-ingest-token';
  if hdr_token is null then
    raise exception 'missing x-ingest-token header';
  end if;

  select user_id into uid from public.ingest_tokens where token = hdr_token;
  if uid is null then
    raise exception 'invalid ingest token';
  end if;

  -- <<< DEBUG >>> 把这次 payload 里 name 含 basal / resting energy 的 metric 块原样存下来
  insert into public.ingest_debug(basal_block)
  select jsonb_agg(mm)
  from jsonb_array_elements(coalesce(data -> 'metrics', '[]'::jsonb)) as mm
  where lower(mm ->> 'name') like '%basal%' or lower(mm ->> 'name') like '%resting%';
  -- <<< /DEBUG >>>

  for wk in
    select value from jsonb_array_elements(
      coalesce(data -> 'workouts', data #> '{data,workouts}', '[]'::jsonb)
    ) as t(value)
  loop
    insert into public.watch_workouts(user_id, payload, source)
    values (uid, wk, 'auto')
    on conflict (user_id, dedup_key) do nothing;
    n := n + 1;
  end loop;

  for m in
    select value from jsonb_array_elements(coalesce(data -> 'metrics', '[]'::jsonb)) as t(value)
  loop
    for s in
      select value from jsonb_array_elements(coalesce(m -> 'data', '[]'::jsonb)) as t2(value)
    loop
      if (s ->> 'qty') is not null and (s ->> 'date') is not null then
        insert into public.body_metrics(user_id, metric, date_raw, qty, unit, source)
        values (uid, m ->> 'name', s ->> 'date', nullif(s ->> 'qty','')::numeric, m ->> 'units', s ->> 'source')
        on conflict (user_id, dedup_key) do nothing;
        n := n + 1;
      end if;
    end loop;
  end loop;

  if n = 0 then
    insert into public.watch_workouts(user_id, payload, source)
    values (uid, data, 'auto-raw')
    on conflict (user_id, dedup_key) do nothing;
    n := 1;
  end if;

  return jsonb_build_object('inserted', n);
end;
$$;

grant execute on function public.ingest_watch(jsonb) to anon, authenticated;
