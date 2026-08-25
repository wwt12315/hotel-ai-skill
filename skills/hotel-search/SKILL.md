---
name: hotel-search
description: "用自然语言搜索酒店（hotelbyte 公开 REST API）。支持模糊输入如『东京下周五 2 晚 2 人预算 200』，通过 curl 调 hotelbyte 测试 API，返回带解读的酒店列表。触发词包括『搜酒店』『找酒店』『查一下酒店』『hotel search』『find hotel』。演示环境为 api-test.hotelbyte.com。"
---

# /hotel-search

通过 `curl` 调 hotelbyte 公开 REST API（`api-test.hotelbyte.com`），根据自然语言需求返回酒店列表 + 中文/英文解读。

## 前提条件

1. **工具**：系统需装 `curl` + `jq`。Windows 用 Git Bash；macOS/Linux 直接用。
2. **凭据**：演示环境用 hotelbyte 公开 demo key。Agent 在每次调用前**用户自己 export**（不要写进任何文件）：

```bash
export HOTELBYTE_DEMO_APP_KEY="<your-hotelbyte-demo-app-key>"
export HOTELBYTE_DEMO_APP_SECRET="<your-hotelbyte-demo-app-secret>"
export HOTELBYTE_BASE_URL="https://api-test.hotelbyte.com"
```

> Demo 凭据从 hotelbyte 官方公开渠道获取（[酒店 demo 凭据规范](https://github.com/hotelbyte-com/docs)）；**agent 不允许 commit / 写进任何持久化文件**。本 SKILL.md 用 `${HOTELBYTE_DEMO_APP_KEY}` / `${HOTELBYTE_DEMO_APP_SECRET}` / `${HOTELBYTE_BASE_URL}` 占位。

## 用户输入

```
$ARGUMENTS
```

支持的形态（任选其一，混搭也行）：
- `hotel-search Tokyo 2026-09-24 2026-09-26 2 200 4` —— 目的地 起 止 人数 预算/晚 最低星级
- `hotel-search 北京 下周五 2 晚 2 人 预算 300`
- `hotel-search 我下个月想去巴黎玩 5 天 2 个人`
- `hotel-search --test` —— 用 Tokyo 标准 fixture，回归测试用

## 流程

### 步骤 1：解析自然语言到结构化参数

| 字段 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `destinationName` | 是 | — | 城市名（如 `Tokyo` / `北京`）—— curl body 用 `destinationName` |
| `destinationId` | 否 | — | 已知目的地 ID 时优先用（如 `city:123`）—— curl body 用 `destinationId` |
| `checkIn` | 否 | 今天 + 30 天 | `YYYY-MM-DD`，**必须 > 今天**（演示环境对近期日期有库存） |
| `checkOut` | 否 | checkIn + 2 天 | `YYYY-MM-DD` |
| `roomOccupancies` | 否 | `[{"adultCount":2,"childrenAges":[]}]` | 结构化数组，传给 API |
| `adultCount` | 否 | 2 | 自动包成 `roomOccupancies` |
| `childrenCount` | 否 | 0 | 自动包成 `roomOccupancies` |
| `currency` | 否 | USD | ISO 4217，发给 `-H 'Currency: USD'` |
| `countryCode` | 否 | US | ISO 3166-1 alpha-2，销售国家 |
| `residencyCode` | 否 | US | ISO 3166-1 alpha-2，居住地 |
| `nationalityCode` | 否 | US | ISO 3166-1 alpha-2，下单国籍 |
| `minStarRating` | 否 | 0 | 0-5，**agent 在结果里自己过滤**（API 不接受此参数） |
| `priceLow / priceHigh` | 否 | 0 / 99999 | agent 在结果里自己过滤 |
| `maxRatesPerHotel` | 否 | 3 | curl body 用 `maxRatesPerHotel` |

**日期模糊处理**：含"下周五/下个月/X 天后"时，用 `date -d '+N days'` 计算。**默认用 +30 天**（演示环境对近期日期有库存，`+7d` 偶尔返回空）。

**`destinationName` 缺失或模糊**：反问一次，列出 2-3 个候选。

### 步骤 2：拿 ticket

```bash
TICKET_RESP=$(curl -sS -X POST "${HOTELBYTE_BASE_URL}/api/auth/ticket" \
  -H "Content-Type: application/json" \
  -d "{\"appKey\":\"${HOTELBYTE_DEMO_APP_KEY}\",\"appSecret\":\"${HOTELBYTE_DEMO_APP_SECRET}\",\"ttl\":3600}")

TICKET=$(echo "$TICKET_RESP" | jq -er '.data.ticket')
```

ticket 是 JWT 字符串，3600 秒滑动过期。本 skill 内复用。**不要 commit 响应体里的 ticket**。

### 步骤 3：调 hotelList

```bash
HOTELLIST=$(curl -sS -X POST "${HOTELBYTE_BASE_URL}/api/search/hotelList" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TICKET" \
  -H "Currency: $CURRENCY" \
  -d "{
    \"checkIn\": \"$CHECKIN\",
    \"checkOut\": \"$CHECKOUT\",
    \"countryCode\": \"$COUNTRY_CODE\",
    \"residencyCode\": \"$RESIDENCY_CODE\",
    \"nationalityCode\": \"$NATIONALITY_CODE\",
    \"destinationName\": \"$DESTINATION\",
    \"roomOccupancies\": $ROOM_OCCUPANCIES,
    \"maxRatesPerHotel\": $MAX_RATES,
    \"sortBy\": \"price-asc\"
  }")
```

> 注：`sessionId` 由服务器从 ticket 派生并放进 `data.basic.sessionId`，**不要**手动生成 / 携带。

### 步骤 4：解读响应（关键：先看 `.code`）

**所有 hotelbyte 端点返回统一响应壳**：

```json
{ "code": 0, "msg": "Success", "data": { ... } }
```

- `code: 0` = 成功（HTTP 200）
- `code != 0` = 业务错（多数时候 HTTP 状态镜像 code；例外 `100001111 ARIChanged` 是 HTTP 200）
- 错误响应**可能省略 `data`** 字段

真实响应形态（来自 2026-08-25 演示环境实测 `+30d/+32d` Tokyo 查询）：

**A. 库存可用（`code: 0 + data.result.status: "verified"`）** —— **演示环境实测**

```json
{
  "code": 0, "msg": "",
  "data": {
    "basic": {
      "destination": {"id": "3060702847928529", "name": {"en": "Tokyo"}, "type": "CITY"},
      "sessionId": "S-20260825072825-BS4G7G"
    },
    "result": {"version": "v1", "status": "verified", "reason": "verified", "correlationId": "..."},
    "hasMore": true,
    "list": [
      {
        "id": "1852470996",
        "name": {"en": "Shinjuku Warm Villa I"},
        "address": {"en": "2-26-5 Okubo; Tokyo 169-0072"},
        "rating": null,
        "minPrice": {"currency": "USD", "amount": "60.4"},
        "isAvailable": true,
        "rooms": [
          {
            "roomTypeId": "E2",
            "rates": [
              {
                "ratePkgId": "10000000<HB>-1<HB>E2-NRF|20260924|20260926",
                "refundableMode": "no",
                "rate": {"netRate": {"amount": "30.20", "currency": "USD"},
                         "commissionableRate": {"amount": "33.22", "currency": "USD"},
                         "grossRate": {"amount": "35.70", "currency": "USD"}},
                "totalRate": {"netRate": {"amount": "60.4", "currency": "USD"}, ...},
                "checkIn": "2026-09-24", "checkOut": "2026-09-26",
                "board": {"boardId": "RO", "boardName": {"en": "Room Only"}}
              }
            ]
          }
        ]
      }
    ]
  }
}
```

`result.status: "verified"` 表示酒店 + 价格 + 库存都已 server 端校验通过，可以直接拿 `list[].rooms[].rates[].ratePkgId` 给下游用。

**B. 无库存（`code: 0 + data.result.status: "failed"`）** —— 演示环境对部分日期 / 目的地会回这条

```json
{
  "code": 0,
  "data": {
    "result": {"status": "failed", "reason": "no_availability", "correlationId": "..."}
  }
}
```

**C. 业务错误（`code != 0`）** —— 参数错 / 限流 / 系统错

```json
{"code": 100000400, "msg": "checkIn date cannot be in the past"}
```
或
```json
{"code": 100000429, "msg": "rate limit exceeded"}
```
或
```json
{"code": 100000500, "msg": "system error"}
```

错误码权威定义见 `common/bizerr/define.go`：
- `100000400` ParamErr（400）
- `100000401` AuthenticationErr（401）
- `100000404` NotFoundErr（404）
- `100000429` RateLimitErr（429）
- `100000500` SystemErr（500）

**D. HTTP 错**（4xx/5xx，curl 返回非 200）

`curl -sS` 不带 `-w '%{http_code}'` 时这种少见；如果发生，`curl` exit code 非 0，stdout 是错误 HTML / 空白。报告 HTTP status + 响应体前 500 字。

### 步骤 5：输出

**A 分支**（`result.status: "verified" + list[]` 有内容）：
```bash
# 按 minPrice 升序，挑前 8 家，渲染 markdown 表格
echo "$HOTELLIST" | jq -r '
  .data.list
  | sort_by(.minPrice.amount | tonumber)
  | .[:8]
  | .[] | " \(.id) | \(.name.en // .name.zh // "?") | \(.minPrice.amount) \(.minPrice.currency) | \(.address.en // .address.zh // "")"
'
```

```markdown
# 搜索结果：<destination>，<checkIn> → <checkOut>，<adults> 成人

| # | 酒店 ID | 酒店名 | 起价 | 地址 |
|---|---------|--------|------|------|
| 1 | 1852470996 | Shinjuku Warm Villa I | 60.40 USD | 2-26-5 Okubo; Tokyo 169-0072 |
| ... |

## 下一步
拿到 `list[].rooms[].rates[].ratePkgId` 后跑：
- `/hotel-check-availability <ratePkgId>` 验当前价
- `/hotel-book <ratePkgId> 张三 zhangsan@example.com [--confirm]` 下单

> correlationId=<id> 可用于向 hotelbyte 支持团队核查此请求
> sessionId=<S-...> 是 hotelbyte server 生成的会话标识（无需手动管理）
```

**B 分支**（演示环境无库存）：
```markdown
# 无可预订酒店

**目的地**：<destination>
**日期**：<checkIn> → <checkOut>

API 返回 `result.status: failed / reason: no_availability`。

**建议**：
- 换一个目的地（如 Hong Kong、Bangkok、Singapore 演示库存更密集）
- 把日期往后挪 30-90 天（**默认 +30 天通常有效**，+7 天 / 当天附近常返回空）
- 去掉 `minStarRating` 限制（演示数据星级字段多为 null）
```

**C/D 分支**：报告 `code` + `msg`，让用户改输入。

## 兜底分支汇总

| jq 探测 | 处理 |
|---|---|
| `.code == 0` 且 `.data.result.status == "verified"` 且 `.data.list[]` 非空 | 走 A 分支 |
| `.code == 0` 且 `.data.result.status == "failed"` | 走 B 分支（演示环境无库存） |
| `.code == 0` 但 `.data.list[]` 为空 / 缺 result | 走 B 分支兜底 |
| `.code != 0` | 走 C 分支（业务错），展示 `.code` + `.msg` |
| `curl` exit 非 0 / HTTP 非 2xx | 走 D 分支，报告 status + body 前 500 字 |
| `ticket` 拿不到 / `.data.ticket` 为空 | 走 C 分支，重跑步骤 2 |
| 日期模糊且用户不在场 | 列我假设的日期，等确认（避免在错日期上浪费 API 配额） |

## `--test` 模式

如果 `$ARGUMENTS` 含 `--test`，忽略其余输入，跑标准 fixture：

```
destinationName=Tokyo
checkIn=<今天+30 YYYY-MM-DD>
checkOut=<今天+32 YYYY-MM-DD>
countryCode=US, residencyCode=US, nationalityCode=US
roomOccupancies=[{"adultCount":2,"childrenAges":[]}]
currency=USD, maxRatesPerHotel=3
```

**预期**：A 分支（演示环境 +30/+32d Tokyo 实测有 10 家酒店，价格 $60 起）。

输出顶部加 `[fixture] Tokyo standard dates`。用于回归 / 演示。

## 工具权限建议（agent-aware）

本 skill 仅需要：
- `curl`（必须，调 hotelbyte API）
- `jq`（必须，解析 `{code, msg, data}` 壳 + 抽 `list[]` / `sessionId` / `correlationId`）
- `date`（计算模糊日期）

不要使用 `Bash(*)` 宽权限——这是最小权限原则。

## 诚实契约（按 hotelbyte `agent-dev-contract`）

- **真实调用**：始终走 `curl` 调 `/api/search/hotelList`，**不**返回 mock 数据冒充实测。
- **Gap 优于臆造**：演示环境 `result.status: "failed"` 走 B 分支明确告知，**不**伪造酒店列表。
- **类型化 I/O**：响应字段必须按 `.code` / `.data.result.status` / `.data.list[].rooms[].rates[].ratePkgId` typed 结构读取，不解析自由文本。
- **证据可追溯**：每次返回带 `correlationId=<id>` 和 `sessionId=<id>`，便于向 hotelbyte 支持团队核查。
- **不固守 demo 凭据到任何持久化文件**：demo key 只在用户 shell 环境变量里，agent 不再额外持久化。