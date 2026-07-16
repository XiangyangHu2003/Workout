-- 只读诊断：把 source 字符串每个字符的 Unicode 码点打印出来，
-- 看看"Apple Watch"这几个字符是不是标准 ASCII（U+0041 A, U+0070 p, ... U+0020 空格等），
-- 还是全角字符、不可见字符之类的东西
select distinct
  source,
  length(source) as char_count,
  (
    select string_agg(to_hex(ascii(substr(source, i, 1))), ' ' order by i)
    from generate_series(1, length(source)) as i
  ) as codepoints_hex
from public.body_metrics
where metric = 'basal_energy_burned'
  and source ilike '%watch%'
limit 5;

-- 补充：分别单独测试 "apple" 和 "watch" 两个词是否各自能被找到（不假设中间的分隔符）
select distinct
  source,
  source ilike '%apple%' as has_apple,
  source ilike '%watch%' as has_watch
from public.body_metrics
where metric = 'basal_energy_burned'
  and left(date_raw,10) = '2026-07-07';
