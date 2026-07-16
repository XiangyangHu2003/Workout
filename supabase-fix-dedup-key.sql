-- 修复 body_metrics 的去重键设计缺陷：dedup_key 原来只看 metric+date_raw，没把 source 算进去。
-- 同一分钟内 Apple Watch 分钟级数据和 Fit Profile 体脂秤数据可能共享同一个 date_raw 时间戳，
-- 唯一索引会让先到的那条挡住后到的（on conflict do nothing 静默丢弃，不报错、不提示），
-- 导致晚到的真实数据永远进不了库——这就是体脂秤 BMR 数据消失的根本原因。
--
-- 这里只改 dedup_key 这一个由数据库自动计算的派生列和它上面的唯一索引，
-- 不会读取、修改或删除 metric/date_raw/qty/unit/source/created_at 任何一条已有数据。
-- 注意：这个修复只能防止今后再发生同样的碰撞，无法找回已经因为撞车而从未成功写入的历史数据。

drop index if exists public.body_metrics_user_dedup;

alter table public.body_metrics drop column dedup_key;

alter table public.body_metrics add column dedup_key text generated always as (
  metric || '|' || date_raw || '|' || coalesce(source, '')
) stored;

create unique index if not exists body_metrics_user_dedup
  on public.body_metrics(user_id, dedup_key);
