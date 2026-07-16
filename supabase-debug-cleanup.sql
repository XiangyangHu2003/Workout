-- 收尾：把 ingest_watch 还原成不带调试日志的干净版本，并删掉临时调试表。
-- 这版函数逻辑和 supabase-watch.sql 里的原版完全一致（不再写 ingest_debug）。

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

drop table if exists public.ingest_debug;
