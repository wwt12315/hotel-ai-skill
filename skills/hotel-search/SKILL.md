---
name: hotel-search
description: "用自然语言搜索酒店（hotelbyte hbcli）。支持模糊输入如『东京下周五 2 晚 2 人预算 200』，通过 hbcli 官方 CLI 调用 hotelbyte 测试 API，返回带解读的酒店列表。触发词包括『搜酒店』『找酒店』『查一下酒店』『hotel search』『find hotel』。演示环境为 api-test.hotelbyte.com。"
---

# /hotel-search

通过 hotelbyte 官方 CLI（`hbcli`）调用 hotelbyte 测试 API，根据自然语言需求返回酒店列表 + 中文/英文解读。

## 前提条件

> 本 skill 假设 `hbcli` 已经安装并配好凭据。如未安装，请先执行：

```bash
# 安装（官方一键脚本）
curl -fsSL https://github.com/hotelbyte-com/docs/releases/latest/download/install.sh | bash

# 配置演示凭据（公开 demo key）
hbcli auth set-credentials \
  --app-key hotelbyte_api_demo \
  --app-secret hotelbyte_api_demo

# 可选：切到测试环境（默认 uat，演示 API 用 uat 即可）
# hbcli --env uat ...
```

`hbcli` 会自动管理 ticket（`appKey`/`appSecret` → JWT，过期自动续），agent 无需手动换 token / 带 `Authorization` header。

## 用户输入

```
$ARGUMENTS
```

支持的形态（任选其一，混搭也行）：
- `hotel-search Tokyo 2026-08-28 2026-08-30 2 200 4` —— 目的地 起 止 人数 预算/晚 最低星级
- `hotel-search 北京 下周五 2 晚 2 人 预算 300`
- `hotel-search 我下个月想去巴黎玩 5 天 2 个人`
- `hotel-search --test` —— 用 Tokyo 标准 fixture，回归测试用

## 流程

### 步骤 1：解析自然语言到结构化参数

| 字段 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `destinationName` | 是 | — | 城市名（如 `Tokyo` / `北京`）—— `hbcli` 用 `--destination-name` |
| `destinationId` | 否 | — | 已知目的地 ID 时优先用（如 `city:123`） |
| `checkIn` | 否 | 今天 + 7 天 | `YYYY-MM-DD`，**必须 > 今天** |
| `checkOut` | 否 | checkIn + 2 天 | `YYYY-MM-DD` |
| `roomOccupancies` | 否 | `[{"adultCount":2,"childrenAges":[]}]` | 结构化数组 |
| `adultCount` | 否 | 2 | 自动包成 `--room-occupancies` |
| `childrenCount` | 否 | 0 | 自动包成 `--room-occupancies` |
| `currency` | 否 | USD | ISO 4217 |
| `language` | 否 | en-US（中文输入 → zh-CN） | IETF BCP 47 |
| `countryCode` | 否 | US（演示建议） | `hbcli` 必传：销售国家 |
| `nationalityCode` | 否 | US（演示建议） | `hbcli` 必传：下单国籍 |
| `residencyCode` | 否 | US（演示建议） | `hbcli` 必传：居住地 |
| `minStarRating` | 否 | 0 | 0-5（`hbcli` 不直接接受，agent 在结果里自己过滤） |
| `priceLow / priceHigh` | 否 | 0 / 99999 | agent 在结果里自己过滤 |
| `maxRatesPerHotel` | 否 | 3 | `--max-rates-per-hotel` |

**日期模糊处理**：含"下周五/下个月/X 天后"时，用 `date` 命令计算。今天是 2026-08-21（周五），所以"下周五"= 2026-08-28。

**`destinationName` 缺失或模糊**：反问一次，列出 2-3 个候选。

### 步骤 2：调用 `hbcli search hotel-list`

```bash
hbcli --json search hotel-list \
  --check-in 2026-08-28 \
  --check-out 2026-08-30 \
  --country-code US \
  --nationality-code US \
  --residency-code US \
  --destination-name "Tokyo" \
  --room-occupancies '[{"adultCount":2,"childrenAges":[]}]' \
  --max-rates-per-hotel 3 \
  --sort-by price-asc
```

如果用户已给出 `--destination-id`（如从历史对话里拿出 `city:123`），把 `--destination-name` 换成 `--destination-id`。

### 步骤 3：解读响应（关键：先看 `result.status`）

`hbcli --json` 把 HTTP 响应包成 `{ok, status, body}` 三段。`hbcli` 在非 2xx 时返回 `{"ok": false, "error": "..."}`。

真实响应形态（来自实测 2026-08-20）：

**A. 库存可用（成功）**：
```json
{
  "ok": true,
  "status": 200,
  "body": {
    "code": 0,
    "data": {
      "list": [{"hotelId": "...", "name": "...", "minPrice": 185, ...}],
      "result": {"version": "v1", "status": "success", "correlationId": "..."}
    }
  }
}
```

**B. 无库存（演示环境常见）**：
```json
{
  "ok": true,
  "status": 200,
  "body": {
    "code": 0,
    "data": {
      "result": {"version": "v1", "status": "failed", "reason": "no_availability",
                 "correlationId": "...", "provenance": [...]},
      "clientIP": "...", "checkIn": "2026-09-10", "checkOut": "2026-09-12"
    }
  }
}
```

**C. 参数错误**：
```json
{"ok": false, "status": 400, "error": "{\"code\":100000400,\"msg\":\"checkIn date cannot be in the past...\"}"}
```

### 步骤 4：输出

**A 分支**（拿到 list）：
```markdown
# 搜索结果：<destination>，<checkIn> → <checkOut>，<adults> 成人，预设 ≤ <price>/晚，≥ <star> 星

| # | 酒店 | 星级 | 价格/<currency> | 评分 | 位置 |
|---|------|------|----------------|------|------|
| 1 | <name> | ⭐<n> | <minPrice> | <reviewScore> | <address> |
| ... |

## 推荐
<1-2 段解读>

> 由 hbcli 调 hotelbyte 测试 API 实时返回
> correlationId=<id> 可用于向 hotelbyte 支持团队报告
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
- 联系 hotelbyte 申请真实 partner key（演示凭据数据稀疏）

> correlationId=<id> 可用于向 hotelbyte 支持团队报告此请求
```

**C 分支**（参数错）：报告 `ok: false` + `error` + 解析后的 `code`/`msg`，让用户改输入。

## 兜底分支汇总

| 现象 | 处理 |
|------|------|
| `body.data.list` 不存在或为空 | 走 B 分支（兜底） |
| `body.code != 0` | 走 C 分支（参数错 / 业务异常） |
| `hbcli ok == false` | 走 C 分支（HTTP 4xx/5xx，`hbcli` 已自动打印 `✗ [status] /path: body`） |
| `hbcli` 退出码非 0 | 重跑一次 + 报告 stderr |
| 日期模糊且用户不在场 | 列我假设的日期，等确认（避免在错日期上浪费 API 配额） |

## `--test` 模式

如果 `$ARGUMENTS` 含 `--test`，忽略其余输入，跑标准 fixture：

```
destinationName=Tokyo, checkIn=<今天+30 YYYY-MM-DD>, checkOut=<今天+32 YYYY-MM-DD>,
roomOccupancies=[{"adultCount":2,"childrenAges":[]}],
countryCode=US, nationalityCode=US, residencyCode=US,
currency=USD, language=en-US, maxRatesPerHotel=5
```

输出顶部加 `[fixture] Tokyo standard dates`。用于回归 / 演示。

## 工具权限建议（agent-aware）

本 skill 仅需要：
- `hbcli`（必须，调 hotelbyte API；自带 ticket 管理 + JSON 输出）
- `date`（计算模糊日期）

不要使用 `Bash(*)` 宽权限——这是最小权限原则。

## 诚实契约（按 hotelbyte `agent-dev-contract`）

- **真实调用**：始终走 `hbcli` 调 `/api/search/hotelList`，**不**返回 mock 数据冒充实测。
- **Gap 优于臆造**：演示环境 `no_availability` 走 B 分支明确告知，**不**伪造酒店列表。
- **类型化 I/O**：响应字段必须按 `body.data.result.status` / `body.data.list[]` typed 结构读取，不解析自由文本。
- **证据可追溯**：每次返回带 `correlationId=<id>`，便于向 hotelbyte 支持团队核查。
- **不固守 demo 凭据到任何持久化文件**：demo key 只在 `~/.hotelbyte-cli/credentials.json`，agent 不再额外持久化。