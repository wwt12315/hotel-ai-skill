---
name: hotel-book
description: "通过 curl 下单预订酒店。默认 Dry-run（输出准备下单清单让用户确认），加 --confirm 才真下单并轮询订单状态。在 hotel-check-availability 之后调用。触发词包括『下单』『预订』『book hotel』『make reservation』。演示环境为 api-test.hotelbyte.com。"
---

# /hotel-book

通过 `curl` 调 hotelbyte 公开 REST API 预订酒店。**默认 Dry-run 模式**——只输出"准备下单"清单让你确认；加 `--confirm` 才真下单、调 `/api/trade/book`、并轮询订单状态。

下游衔接：把 `customerReferenceNo` 保留好，取消订单时 `/hotel-cancel` 要用。

## 前提条件

1. **工具**：`curl` + `jq` + `uuidgen`（`uuidgen` 在 macOS/Linux 自带；Windows Git Bash 自带；PowerShell 用 `[guid]::NewGuid().Guid`）。
2. **凭据**：演示环境用 hotelbyte 公开 demo key。Agent 在每次调用前**用户自己 export**：

```bash
export HOTELBYTE_DEMO_APP_KEY="<your-hotelbyte-demo-app-key>"
export HOTELBYTE_DEMO_APP_SECRET="<your-hotelbyte-demo-app-secret>"
export HOTELBYTE_BASE_URL="https://api-test.hotelbyte.com"
```

> Demo 凭据从 hotelbyte 官方公开渠道获取；**agent 不允许 commit / 写进任何持久化文件**。

## 用户输入

```
$ARGUMENTS
```

支持的形态（Dry-run）：
- `/hotel-book <ratePkgId> 张三 zhangsan@example.com` —— 1 间房 1 个客人
- `/hotel-book <ratePkgId> 张三 zhangsan@example.com 2 rooms` —— 2 间房
- `/hotel-book <ratePkgId> 张三 zhangsan@example.com 1 3` —— 1 间房 3 个客人

真下单（加 `--confirm`）：
- `/hotel-book <ratePkgId> 张三 zhangsan@example.com --confirm`
- `/hotel-book <ratePkgId> 张三 zhangsan@example.com 2 rooms --confirm`

测试模式：
- `/hotel-book --test` —— 用固定 fixture 跑 Dry-run 输出

## 字段说明

| 字段 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `ratePkgId` | 是 | — | 必须从 `/hotel-check-availability` 的成功响应来，**不能瞎编** |
| `holder.firstName` | 是 | — | 预订联系人名 |
| `holder.lastName` | 是 | — | 预订联系人姓 |
| `holder.email` | 否 | — | 邮箱（酒店发确认信） |
| `guests[].firstName` | 是 | — | 入住客人名（每间房至少 1 个） |
| `guests[].lastName` | 是 | — | 入住客人姓 |
| `guests[].roomIndex` | 是 | — | 房间索引（**从 1 开始**） |
| `customerReferenceNo` | 自动生成 | — | UUID4，**幂等键**——agent 用 `uuidgen` 自动生成 |
| `roomCount` | 否 | 1 | 房间数 |
| `--confirm` | 否 | false | 加这个标志才真下单 |

**中文姓名处理**（**干跑阶段就要确认**）：
- "张三" → `firstName: "San", lastName: "Zhang"`（拼音）
- agent 自身拼音能力不强，**反问用户确认拼音写法**——CJK 字符传给酒店可能拒收

**`ratePkgId` 缺失或模糊**：反问一次。它是长字符串（演示环境实测格式如 `10000000<HB>-1<HB>E2-NRF|20260924|20260926`），从 `/hotel-check-availability` 的输出复制。

## ⚠️ 演示环境实测注意

实测发现 hotelbyte 演示 API 的 `book` 端点：

- **演示环境的 book 调用返回 `code: 100000500 / msg: "system error"`** —— 2026-08-25 用真实 ratePkgId 实测
- 这是演示环境基础设施限制（演示环境的 book 端点不真下单）
- 真实生产环境才能看到 status: 1（Confirming）/ 2（Confirmed）/ 4（Failed）/ 5（CancelFailed）

**演示环境下** book 调用大概率返回**分支 E（100000500 system error）** 或 **分支 C（100000400 param error）**。

## 流程

### 步骤 1：解析自然语言

解析 `$ARGUMENTS` 得到：
- `ratePkgId`
- `holder.firstName / lastName / email`
- `roomCount`、`guestCount`
- `guests[]`（每个房间 1 个客人，从 holder 复制）
- 是否有 `--confirm` 标志

如果 `ratePkgId` 缺失：反问。
如果姓名含中文字符（不是 ASCII）：**反问一次拼音**。

### 步骤 2：Dry-run（默认）—— 输出"准备下单"清单

```bash
CUSTOMER_REF=$(uuidgen)
```

```markdown
# 🛒 准备下单（Dry-run，未执行）

**酒店**：<hotelId>（建议跑 `/hotel-search` 拿酒店名）
**报价**：<ratePkgId>
**价格**：<显示讲解：从 checkAvail 的 snapshot 来>

**预订联系人**：
- 姓名：<lastName> <firstName>
- 邮箱：<email>

**房间 & 客人**：
- 房间 1：<guest 姓名>
- 房间 2：<guest 姓名>（如果有 2 间房）
- ...

**订单 ID（先生成）**：
- customerReferenceNo：<uuid>（幂等键，由 agent 自动生成）

---

**确认下单吗？** 加 `--confirm` 重跑：

```bash
/hotel-book <ratePkgId> 张三 zhangsan@example.com --confirm
```

或者改一下：
- 改房间数：`/hotel-book <ratePkgId> 张三 zhangsan@example.com 2 rooms --confirm`
- 改客人姓名：`/hotel-book <ratePkgId> 李四 lisi@example.com --confirm`

> ⚠️ 演示环境提示：hotelbyte 演示 API 的 book 端点对真实 ratePkgId 也返回 `code: 100000500 system error`（实测 2026-08-25）。这是预期的——证明 toolchain 通了。
```

**Dry-run 模式到此结束**——**不调 `/api/trade/book`**，不消耗对方 API 配额。

### 步骤 3：真下单（仅 `--confirm` 模式）

#### 3a：拿 ticket

```bash
TICKET=$(curl -sS -X POST "${HOTELBYTE_BASE_URL}/api/auth/ticket" \
  -H "Content-Type: application/json" \
  -d "{\"appKey\":\"${HOTELBYTE_DEMO_APP_KEY}\",\"appSecret\":\"${HOTELBYTE_DEMO_APP_SECRET}\",\"ttl\":3600}" \
  | jq -er '.data.ticket')
```

#### 3b：构造请求体（文档 `BookReq`）

```bash
HOLDER=$(jq -nc --arg fn "$FIRSTNAME" --arg ln "$LASTNAME" --arg em "$EMAIL" \
  '{firstName: $fn, lastName: $ln, email: $em}')

GUESTS=$(jq -nc --arg fn "$FIRSTNAME" --arg ln "$LASTNAME" \
  '[{roomIndex: 1, firstName: $fn, lastName: $ln}]')

BODY=$(jq -nc --arg rpk "$RATE_PKG_ID" --argjson holder "$HOLDER" --argjson guests "$GUESTS" \
  --arg uuid "$CUSTOMER_REF" \
  '{ratePkgId: $rpk, customerReferenceNo: $uuid, holder: $holder, guests: $guests}')
```

> 用 `jq -nc` 构造 body 避免手写 JSON 转义出错。

#### 3c：调 book

```bash
BOOK=$(curl -sS -X POST "${HOTELBYTE_BASE_URL}/api/trade/book" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TICKET" \
  -d "$BODY")
```

### 步骤 4：解读 book 响应（5 个分支）

**所有 hotelbyte 端点返回统一响应壳**：

```json
{ "code": 0, "msg": "Success", "data": { ... } }
```

#### 分支 A：下单成功（`code: 0 + data.hotelOrder.status: 1`）—— 真实生产环境

**演示环境无法验证**（演示 book 端点返回 `100000500`）。预期响应：

```json
{
  "code": 0,
  "data": {
    "hotelOrder": {
      "status": 1,
      "statusRemark": "正在确认中",
      "checkIn": "2026-09-24",
      "checkOut": "2026-09-26",
      "nightCount": 2,
      "roomCount": 1,
      "bookingTime": "2026-08-25T08:00:00Z",
      "platformReferenceNo": "PLT202608250001234",
      "customerReferenceNo": "abcdef-1234-5678-...",
      "supplierReferenceNo": "SUP12345",
      "netRate": {"currency": "USD", "amount": 60.40},
      "grossRate": {"currency": "USD", "amount": 71.41}
    }
  }
}
```

**拿到 `data.hotelOrder.status == 1` 后立即进入轮询**（步骤 5）。

#### 分支 B：ARI 变更（`code: 100001111`）—— 真实生产环境

**演示环境无法验证**（演示 book 返回 system error 不返回 ARI changed）。预期响应：

```json
{"code": 100001111, "msg": "ARI changed"}
```

**注意**：ARI 变更的 HTTP 状态是 **200**（不是 409！），但 `.code` 是 100001111。

输出：

```markdown
# ❌ 下单失败：ARI 已变更

API 返回 `code: 100001111`。

**含义**：在你 verify 之后到下单之前的几秒，价格或库存又变了。

**建议**：
- 重新跑 `/hotel-check-availability <ratePkgId>`
- 拿到新价格后用新 snapshot 重新 `/hotel-book --confirm`
- 或者换 ratePkgId（换个房型）
```

不进入轮询。

#### 分支 C：参数错误（`code: 100000400`）—— 可能

预期响应：

```json
{"code": 100000400, "msg": "param error"}
```

输出：

```markdown
# 参数错误

API 返回 `code: 100000400`, `msg: "param error"`。

**含义**：ratePkgId 是假的或 holder/guests 格式错。

**生产环境**：
- 重新跑 `/hotel-search` 拿真实 ratePkgId
- 用真实 ratePkgId 重新 `/hotel-check-availability` → `/hotel-book --confirm`
```

不进入轮询。

#### 分支 D：下单失败（`code: 0 + data.hotelOrder.status: 4`）—— 真实生产环境

**演示环境无法验证**。预期响应：

```json
{
  "code": 0,
  "data": {
    "hotelOrder": {
      "status": 4,
      "statusRemark": "供应商拒绝预订",
      "platformReferenceNo": "PLT...",
      "customerReferenceNo": "..."
    }
  }
}
```

输出：

```markdown
# ❌ 下单失败（status: 4）

**订单已生成但供应商拒绝**：
- platformReferenceNo：<id>
- customerReferenceNo：<id>
- statusRemark：<原因>

**可能原因**：
- 库存已清空（最常见）
- 供应商主动拒绝（信用卡、超售、价格不匹配）

**建议**：
- 换一家酒店（重新 `/hotel-search`）
- 保留 `customerReferenceNo` 便于 hotelbyte 客服排查
```

不进入轮询（4 = Failed 是终态）。

#### 分支 E：系统错误 / API 异常 —— **演示环境实测**

**实测响应**（演示环境对真实 ratePkgId 的 book 调用）：

```json
{"code": 100000500, "msg": "system error"}
```

或：
- `code: 100000504` + msg `timeout` —— 504 timeout（trade 端点专用）
- `code: 100000429` —— 限流
- HTTP 401/403/500 —— 凭据 / 权限 / 上游故障

输出：

```markdown
# API 请求失败

`.code`：<code>
`.msg`：<msg>

**演示环境下常见**：
- `100000500 system error`：演示环境 book 端点基础设施限制（**实测必然**）
- `100000504 timeout`：供应商响应慢，可重试
- `100000429`：限流，等 30 秒重试

**建议**：
- 演示环境：本分支**必然**返回，证明 toolchain 通了
- 生产环境：换 ratePkgId 重试；持续失败联系 hotelbyte 客服
```

不进入轮询。

### 步骤 5：轮询订单状态（仅分支 A 触发）

当 book 响应 `data.hotelOrder.status == 1`（Confirming）时，**立即进入轮询**：

```bash
CUSTOMER_REF="<customerReferenceNo>"

for i in $(seq 1 18); do
  RESP=$(curl -sS -X POST "${HOTELBYTE_BASE_URL}/api/trade/queryOrders" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TICKET" \
    -d "{\"customerReferenceNos\":[\"$CUSTOMER_REF\"]}")
  
  STATUS=$(echo "$RESP" | jq -r '.data.orders[0].status // 0')
  echo "Attempt $i (every 10s): status=$STATUS"
  
  if [ "$STATUS" = "2" ] || [ "$STATUS" = "3" ] || [ "$STATUS" = "4" ]; then
    break
  fi
  sleep 10
done
```

> 注：`queryOrders` 实际是 **POST**（不是 GET），见 `public-openapi.yaml:7443-7551`。

**轮询退出条件**：
- `status: 2` (Confirmed) → ✅ 成功
- `status: 4` (Failed) → ❌ 失败
- `status: 3` (Cancelled) → 不应该出现（book 不会让订单变 cancelled）
- 18 次都没动 → 还在 Confirming（罕见）

**轮询输出**：

```markdown
# 📋 订单状态轮询

每次 10 秒，最多 18 次（3 分钟）：

| 第 i 次 | status | 说明 |
|--------|--------|------|
| 1 | 1 (Confirming) | 等待供应商确认 |
| 2 | 1 (Confirming) | ... |
| ... | ... | ... |
| 8 | 2 (Confirmed) | ✅ 已确认 |

**最终结果**：✅ 已确认

**订单详情**：
- platformReferenceNo：<id>
- customerReferenceNo：<id>
- supplierReferenceNo：<id>
- hotelConfirmNo：<id>（酒店确认号，发给酒店入住时要这个）
- checkIn：<date>
- checkOut：<date>
- totalRate：<amount> <currency>
- 酒店：<name> (<address>)

**下一步**：
- 取消订单：`/hotel-cancel <customerReferenceNo> <supplierReferenceNo> [--confirm]`
```

### 步骤 6：写入本地订单快照（仅 `--confirm` 模式 + 仅分支 A 成功）

保存订单快照到 `<project>/.claude/orders/<customerReferenceNo>.json`，便于后续 `/hotel-cancel` 用：

```bash
ORDERS_DIR="<project>/.claude/orders"
mkdir -p "$ORDERS_DIR"
echo "$BOOK" | jq '.data.hotelOrder' > "$ORDERS_DIR/$CUSTOMER_REF.json"
```

> **不**写入 `.claude/memory.db`（敏感数据不进 memory）。`<project>` 由 agent 从 cwd 推断；写入本地文件**不**等于 commit，agent 不会把含 ticket / 真实 ID 的文件 commit。

## 兜底分支汇总

| 探测 | 处理 |
|---|---|
| `.code == 0` 且 `.data.hotelOrder.status == 1` | 走 A 分支 → 轮询（**真实生产环境**） |
| `.code == 0` 且 `.data.hotelOrder.status == 4` | 走 D 分支（失败，**真实生产环境**） |
| `.code == 100001111` | 走 B 分支（ARI 变更，**真实生产环境**） |
| `.code == 100000400` | 走 C 分支（参数错） |
| `.code == 100000500` 或 `.code == 100000504` 或其他非 0 | 走 E 分支（API 异常 / **演示环境实测**） |
| `curl` exit 非 0 / HTTP 非 2xx | 走 E 分支 |
| `ratePkgId` 含空格 / 看起来不对 | 反问："ratePkgId 是从 /hotel-check-availability 复制的长字符串" |
| 轮询 18 次仍未确定状态 | 报告"超时"，保留 `customerReferenceNo` 让用户手动查 |

## `--test` 模式

如果 `$ARGUMENTS` 含 `--test`，跑 Dry-run 输出（**不真下单**）：

```
ratePkgId=10000000<HB>-1<HB>E2-NRF|20260924|20260926（演示环境 /hotel-search 返回的真实 ratePkgId）
holder=张三 zhangsan@example.com
1 间房 1 个客人
```

输出顶部加 `[fixture] book dry-run`。用于演示下单流程。**不真下单**——演示环境 book 端点对真实 ratePkgId 也返回 system error，避免浪费。

## 不要做的事

- **不要默认真下单**——必须 `--confirm` 标志
- **不要跳过 `/hotel-check-availability`**——强烈建议先 verify 一次
- **不要把演示凭据写进任何文件 / 文档 / commit**
- **不要用 `Bash(*)` 宽权限**——本命令只能调 `curl` + `jq` + `uuidgen` + `sleep`
- **不要硬编码中文姓名** —— CJK 字符传给酒店可能拒收，**反问用户拼音**

## 已知限制

- **演示环境的 book 调用必然失败**（返回 `code: 100000500 system error`）——2026-08-25 实测确认。演示环境基础设施限制。
- 真实生产环境才能看到 → status 1 / 2 / 4 / 5 全部分支。
- 轮询超时 3 分钟。**真实的 confirm 可能需要 5-15 分钟**（供应商人工审单）。如果超时，保留 `customerReferenceNo` 让用户用 hotelbyte 客服或 `/hotel-cancel` 验证。
- 中文姓名 → 拼音的转换依赖 LLM 能力，**不保证准确**。商用场景建议让客户在网页上自行输入。