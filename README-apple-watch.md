# 练迹 · Apple Watch 数据接入指南

把 Apple Watch 每次训练的**心率 / 活动能量 / 时长**自动同步进练迹。

## 原理

```
Apple Watch → iPhone「健康」App → Health Auto Export(App)
   → POST 到 Supabase 接口 → watch_workouts 表（存原始 JSON）
   → 练迹读取 + 网页端解析 → 历史页「⌚ Apple Watch」区块显示
```

设计上**后端只存原始数据，字段解析全在网页端**，日后调整字段映射不用改数据库。

---

## 一次性配置（三步）

### 第 1 步：建后端

1. 打开 [Supabase 控制台](https://supabase.com/dashboard) → 你的项目
2. 左侧 **SQL Editor** → **New query**
3. 把项目里的 `supabase-watch.sql` 全部内容粘贴进去 → **Run**

这会创建：
- `watch_workouts` 表（存手表训练，按账号隔离）
- `ingest_tokens` 表（设备同步令牌）
- `ingest_watch` 接口（接收手机推送的数据）

### 第 2 步：在练迹里生成同步令牌

1. 登录练迹（同一个账号）
2. **设置** 页 → **Apple Watch 同步** 卡片 → **生成同步令牌**
3. 弹窗里有现成的 **URL** 和 **4 行请求头**，点一下即可复制

> ⚠️ 令牌只显示这一次，先复制保存好。

### 第 3 步：配置 iPhone 上的 Health Auto Export

1. App Store 搜索安装 **Health Auto Export – JSON+CSV**
2. 新建一个 **Automation** → 选 **REST API**
3. 按练迹弹窗里给的填写：

| 字段 | 值 |
|------|-----|
| **URL** | `https://<你的项目>.supabase.co/rest/v1/rpc/ingest_watch` |
| **Header** `apikey` | 你的 publishable / anon key |
| **Header** `x-ingest-token` | 练迹生成的同步令牌 |
| **Header** `Content-Type` | `application/json` |

> 注意：**不要**再加 `Prefer: params=single-object` 头。接口参数名已设为 `data`，正好对应 Health Auto Export 请求体顶层的 `data` 键；多加 Prefer 反而会报 `PGRST202 function not found`。

4. **数据类型**选 **Workouts**，**格式**选 **JSON**
5. 触发方式选「训练结束后自动导出」（或按小时定时）

配好后，每次用 Apple Watch 练完（例如「力量训练 / Traditional Strength Training」），数据会自动进入练迹 → **历史** 页 → **⌚ Apple Watch** 区块。

---

## 体脂秤 / 身体成分（Health Metrics）

如果你有体脂秤（Fit Profile 等），在 Health Auto Export 里**再建一个 Automation**，选 **REST API**，**URL 和请求头与上面完全一样**（同一个接口、同一个令牌），区别只在：

- **数据类型**选 **Health Metrics**（不是 Workouts）
- 勾选想同步的指标：Body Mass、Body Fat Percentage、BMI、Lean Body Mass、Muscle Mass、Skeletal Muscle Mass、Body Water、Bone Mass、Basal Metabolic Rate、Visceral Fat 等
- **格式** JSON

数据会进入练迹 → **身体** 页 → **⚖️ 体脂秤** 区块（按天分组，点开看当天全部身体成分）。

> 后端同一个 `ingest_watch` 接口会自动区分 workouts 和 metrics，无需额外配置。指标标签未识别时会按原始英文名显示——把一份真实 Health Metrics 导出 JSON 发给开发者即可补上中文名。

---

## 想先试试效果（不等自动化）

设置页「Apple Watch 同步」卡片里有 **导入手表 JSON** 按钮：
在 Health Auto Export 里手动导出一次 workout 存成 `.json` 文件，直接导入即可立即看到效果。

---

## 常见问题

- **点「生成同步令牌」报错**：多半是第 1 步的 `supabase-watch.sql` 还没执行。
- **手表数据没出现**：确认 Health Auto Export 里 URL / 令牌 / 请求头填写正确；数据类型是否选了 Workouts；练迹是否登录的是同一个账号。
- **心率/卡路里显示「—」或距离单位不对**：不同版本 Health Auto Export 的字段名和单位可能不同。把一份真实导出的 workout JSON 发给开发者，几行代码即可精确适配（无需改数据库）。

---

## 涉及文件

- `supabase-watch.sql` — 后端建表与接口脚本
- `index.html` — 练迹前端（设置页同步卡、历史页手表区块、`parseWatchPayload` 解析）
