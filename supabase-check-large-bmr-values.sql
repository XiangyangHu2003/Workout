-- 只读诊断：不管 source 字符串、不管日期，直接找 basal_energy_burned 里数值明显偏大（体脂秤 BMR 量级）的记录
-- 用这个绕开所有字符串匹配和日期分组可能带来的干扰，看这些大数值记录到底还在不在、date_raw/source 具体是什么
select metric, date_raw, qty, unit, source, created_at, length(source) as source_len
from public.body_metrics
where metric = 'basal_energy_burned'
  and qty > 1000
order by created_at;
