# 练迹（Workout）

一个单文件健身记录网页，支持本地离线使用、Supabase 账号同步，以及通过 Health Auto Export 接入 Apple Watch 训练和健康指标。

## 功能

- 训练计划与训练记录
- IndexedDB 本地离线缓存
- Supabase 账号登录与跨设备同步
- Apple Watch 训练数据导入与自动同步
- 体重、体脂、BMI、BMR 等 Health Metrics 展示
- 按日聚合步数、活动能量、静息能量等指标

## 项目文件

| 文件 | 用途 |
| --- | --- |
| `index.html` | 完整前端，可直接作为静态网站部署 |
| `supabase-schema.sql` | 账号云同步所需的表、RLS 策略和触发器 |
| `supabase-watch.sql` | Apple Watch / Health Metrics 所需的表、视图、RLS 策略和接收接口 |

两个 SQL 文件均可重复执行。仓库不包含 Supabase 密钥或用户数据。

## 快速开始

直接打开 `index.html` 可使用本地功能。若要启用账号同步和 Apple Watch 接入：

1. 创建 Supabase 项目。
2. 在 Supabase Dashboard 的 **SQL Editor** 中先完整执行 `supabase-schema.sql`。
3. 再完整执行 `supabase-watch.sql`。
4. 将 `index.html` 中的 Supabase URL 和 publishable / anon key 配置为自己的项目。
5. 把 `index.html` 部署到任意静态托管服务。

> `supabase-watch.sql` 包含旧版 `body_metrics` 去重键的自动迁移。已有部署也应重新执行最新版脚本，以免同一时间、不同来源的健康数据发生冲突。

## Apple Watch 自动同步

### 1. 生成令牌

登录练迹后，进入 **设置 → Apple Watch 同步 → 生成同步令牌**。令牌只显示一次，请立即复制保存。

### 2. 配置 Health Auto Export

在 iPhone 安装 **Health Auto Export – JSON+CSV**，新建 REST API Automation：

| 字段 | 值 |
| --- | --- |
| URL | `https://<你的项目>.supabase.co/rest/v1/rpc/ingest_watch` |
| `apikey` | Supabase publishable / anon key |
| `x-ingest-token` | 练迹生成的同步令牌 |
| `Content-Type` | `application/json` |

不要添加 `Prefer: params=single-object` 请求头，否则可能出现 `PGRST202 function not found`。

训练同步请选择 **Workouts** 和 **JSON** 格式。可设置训练结束后自动导出，也可按小时执行。

### 3. 同步身体指标

如需同步体脂秤或健康指标，再创建一个使用相同 URL 和请求头的 Automation：

- 数据类型选择 **Health Metrics**。
- 格式选择 **JSON**。
- 按需勾选 Body Mass、Body Fat Percentage、BMI、Lean Body Mass、Muscle Mass、Body Water、Bone Mass、Basal Metabolic Rate、Visceral Fat 等指标。

同一个 `ingest_watch` 接口会自动区分 workouts 与 metrics。训练原始 JSON 存入 `watch_workouts`；结构化健康采样存入 `body_metrics`，前端读取按日聚合视图。

## 手动导入测试

在 Health Auto Export 中导出一份 workout JSON，然后在 **设置 → Apple Watch 同步 → 导入手表 JSON** 中选择该文件，无需等待自动化即可验证展示效果。

## 常见问题

- **生成同步令牌失败**：确认两个 SQL 文件已按顺序执行，并且当前用户已登录。
- **自动同步没有数据**：检查 URL、`apikey`、`x-ingest-token`、JSON 格式和 Automation 数据类型。
- **心率、卡路里或距离显示异常**：Health Auto Export 不同版本的字段可能不同，可根据真实导出 JSON 调整 `index.html` 中的解析逻辑。
- **早期健康数据缺失或 BMR 异常**：重新执行最新版 `supabase-watch.sql`，并确认 Health Auto Export 已重新发送对应时间段的数据；去重修复无法恢复过去从未成功写入的数据。

## 安全说明

- 数据表已启用 Row Level Security，登录用户只能访问自己的数据。
- `x-ingest-token` 相当于设备写入凭证，不要提交到 GitHub 或公开分享。
- 前端只能使用 Supabase publishable / anon key，绝不要把 `service_role` key 写进网页或仓库。
