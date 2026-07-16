-- 练迹：第一版账号云同步数据结构
-- 在 Supabase Dashboard > SQL Editor > New query 中执行整个文件。

create table if not exists public.user_app_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  revision bigint not null default 1,
  updated_at timestamptz not null default now()
);

comment on table public.user_app_state is
  '每个账号一份完整的练迹应用状态；IndexedDB 作为设备离线缓存。';

-- 浏览器能够访问该表，但最终访问权限由下方 RLS 策略决定。
alter table public.user_app_state enable row level security;

revoke all on table public.user_app_state from anon;
grant select, insert, update, delete on table public.user_app_state to authenticated;

drop policy if exists "read own app state" on public.user_app_state;
create policy "read own app state"
on public.user_app_state
for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "insert own app state" on public.user_app_state;
create policy "insert own app state"
on public.user_app_state
for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "update own app state" on public.user_app_state;
create policy "update own app state"
on public.user_app_state
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "delete own app state" on public.user_app_state;
create policy "delete own app state"
on public.user_app_state
for delete
to authenticated
using ((select auth.uid()) = user_id);

-- 每次更新时自动刷新时间，并递增版本号，便于设备间判断新旧。
create or replace function public.touch_user_app_state()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  new.revision = old.revision + 1;
  return new;
end;
$$;

drop trigger if exists touch_user_app_state_trigger on public.user_app_state;
create trigger touch_user_app_state_trigger
before update on public.user_app_state
for each row execute function public.touch_user_app_state();

