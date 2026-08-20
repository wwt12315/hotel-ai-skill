---
name: hotel-search
description: 用自然语言搜索酒店（hotelbyte 测试 API）。支持模糊输入如"东京下周五 2 晚 2 人预算 200"，自动换 ticket 并返回带解读的酒店列表。
allowed-tools: Bash(curl:*), Bash(date:*), Bash(uuidgen:*)
---

# /hotel-search

调用 hotelbyte 公开测试 API，根据自然语言需求返回酒店列表 + 中文/英文解读。

## API 配置

- Base URL: `https://api-test.hotelbyte.com`
- AppKey: `hotelbyte_api_demo`
- AppSecret: `hotelbyte_api_demo`
- 业务请求 Header 集合：
  - `Authorization: Bearer <ticket>`（从 `/api/auth/ticket` 拿到的完整字符串，原样使用，含 `ST:` 前缀）
  - `Session-Id: <uuid4>`（每次搜索新生成）
  - `Language: <IETF BCP 47>`（中文输入用 `zh-CN`，默认 `en-US`）
  - `Currency: <ISO 4217>`（默认 `USD`）
  - `Content-Type: application/json`

> **本机环境提示**：ZCode 自带 WebFetch 工具证书过期（`CERT_HAS_EXPIRED`），无法直连 hotelbyte 测试 API。本命令改用 `curl`（Windows Schannel TLS 正常），`allowed-tools` 已限定 `Bash(curl:*)`。

## 用户输入

```
$ARGUMENTS
```

支持的形态（任选其一，混搭也行）：
- `/hotel-search Tokyo 20260828 20260830 2 200 4` —— 目的地 起 止 人数 预算/晚 最低星级
- `/hotel-search 北京 下周五 2 晚 2 人 预算 300`
- `/hotel-search 我下个月想去巴黎玩 5 天 2 个人`
- `/hotel-search --test` —— 用 Tokyo 标准 fixture，回归测试用

## 流程

### 步骤 1：解析自然语言到结构化参数

| 字段 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `destination` | 是 | — | 城市名或目的地 ID（支持中文如"上海"、"北京"） |
| `checkIn` | 否 | 今天 + 7 天 | `YYYYMMDD`，**必须 > 今天** |
| `checkOut` | 否 | checkIn + 2 天 | `YYYYMMDD` |
| `adultCount` | 否 | 2 | |
| `childrenCount` | 否 | 0 | |
| `currency` | 否 | USD | ISO 4217 |
| `language` | 否 | en-US（中文输入 → zh-CN） | IETF BCP 47 |
| `filter.price.low` | 否 | 0 | |
| `filter.price.high` | 否 | 99999 | |
| `minStarRating` | 否 | 0 | 0-5 |
| `maxRatesPerHotel` | 否 | 3 | |

**日期模糊处理**：含"下周五/下个月/X 天后"时，用 `Bash(date:*)` 计算。今天是 2026-08-20（周四），所以"下周五"= 2026-08-28。

**`destination` 缺失或模糊**：反问一次，列出 2-3 个候选。

### 步骤 2：换 ticket

```bash
curl -sS -k -X POST -H "Content-Type: application/json" \
  -d '{"appKey":"hotelbyte_api_demo","appSecret":"hotelbyte_api_demo","ttl":3600}' \
  https://api-test.hotelbyte.com/api/auth/ticket
```

成功响应：
```json
{"code":0,"msg":"","data":{"ticket":"ST:0Va7n..."}}
```

取 `data.ticket` 完整字符串（含 `ST:` 前缀）。

### 步骤 3：搜索酒店

```bash
curl -sS -k -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ST:0Va7n..." \
  -H "Session-Id: $(uuidgen)" \
  -H "Language: en-US" \
  -H "Currency: USD" \
  -d '{
    "destination": "Tokyo",
    "checkIn": "20260828",
    "checkOut": "20260830",
    "adultCount": 2,
    "childrenCount": 0,
    "currency": "USD",
    "language": "en-US",
    "filter": { "price": { "low": 0, "high": 99999 } },
    "minStarRating": 4,
    "maxRatesPerHotel": 3
  }' \
  https://api-test.hotelbyte.com/api/search/hotelList
```

### 步骤 4：解读响应（关键：先看 `data.result.status`）

真实响应形态（来自实测 2026-08-20）：

**A. 库存可用（成功）**：
```json
{"code":0,"msg":"","data":{
  "list":[ {"hotelId":"...","name":"...","minPrice":185,...} ],
  "result":{"version":"v1","status":"success","correlationId":"..."}
}}
```

**B. 无库存（演示环境常见）**：
```json
{"code":0,"msg":"","data":{
  "result":{"version":"v1","status":"failed","reason":"no_availability",
            "correlationId":"...","provenance":[{"source":"supplier","reason":"no_availability","observedAt":"..."}]},
  "clientIP":"...","checkIn":"2026-09-10","checkOut":"2026-09-12"
}}
```

**C. 参数错误**：
```json
{"code":100000400,"msg":"checkIn date cannot be in the past, got: 2025-12-01, today: 2026-08-20"}
```

### 步骤 5：输出

**A 分支**（拿到 list）：
```markdown
# 搜索结果：<destination>，<checkIn> → <checkOut>，<adults> 成人，预设 ≤ <price>/晚，≥ <star> 星

| # | 酒店 | 星级 | 价格/<currency> | 评分 | 位置 |
|---|------|------|----------------|------|------|
| 1 | <name> | ⭐<n> | <minPrice> | <reviewScore> | <address> |
| ... |

## 推荐
<1-2 段解读>

> 由 hotelbyte 测试 API 实时返回，session=<sessionId>
```

**B 分支**（演示环境无库存）：
```markdown
# 无可预订酒店

**目的地**：<destination>
**日期**：<checkIn> → <checkOut>
**筛选**：minStar=<n>, 价格 <low>-<high>

API 返回 `status: failed / reason: no_availability`（演示环境的供应商对所选日期无可用库存）。

**建议**：
- 换一个目的地（如 Hong Kong、Bangkok、Singapore 演示库存更密集）
- 把日期往后挪 30-90 天
- 去掉 `minStarRating` 限制（演示数据往往星级不全）
- 联系 hotelbyte 申请真实 partner key（演示凭据 `hotelbyte_api_demo` 数据稀疏）

> correlationId=<id> 可用于向 hotelbyte 支持团队报告此请求
```

**C 分支**（参数错）：直接报告 `code` 和 `msg`，让用户改输入。

## 兜底分支汇总

| 现象 | 处理 |
|------|------|
| `data.list` 不存在或为空 | 走 B 分支（兜底） |
| `code != 0` | 报告 `code` + `msg`（C 分支） |
| `curl` 退出码非 0 | 重跑一次 + 报告 stderr |
| `data.ticket` 缺失 | 检查 `msg`，可能是 appKey 失效 |
| 日期模糊且用户不在场 | 列我假设的日期，等确认（避免在错日期上浪费 ticket 配额） |

## `--test` 模式

如果 `$ARGUMENTS` 含 `--test`，忽略其余输入，跑标准 fixture：

```
destination=Tokyo, checkIn=<今天+30 YYYYMMDD>, checkOut=<今天+32 YYYYMMDD>,
adults=2, currency=USD, language=en-US, minStarRating=0, maxRatesPerHotel=5
```

输出顶部加 `[fixture] Tokyo standard dates`。用于回归 / 演示。

## 不要做的事

- 不要调 `/api/trade/book`（本 skill 仅做搜索）
- 不要把演示凭据 `hotelbyte_api_demo` 写进任何文件 / 文档 / commit
- 不要用 `Bash(*)` 宽权限——本命令只能调 `curl` / `date` / `uuidgen`
- 不要把 ticket 持久化到 `.claude/memory.db`（凭据类不进 memory）
