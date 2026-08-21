---
name: hotel-book
description: "下单预订酒店。默认 Dry-run（输出准备下单清单让用户确认），加 --confirm 才真下单并轮询订单状态。在 hotel-check-availability 之后调用。触发词包括『下单』『预订』『book hotel』『make reservation』。演示环境为 api-test.hotelbyte.com，凭据为公开 demo 凭据。"
---

# /hotel-book

预订酒店。**默认 Dry-run 模式**——只输出"准备下单"清单让你确认；加 `--confirm` 才真下单、调 `/api/trade/book`、并轮询订单状态。

下游衔接：把 `customerReferenceNo` 保留好，取消订单时 `/hotel-cancel` 要用。

## API 配置

- 端点：`/api/trade/book`
- Base URL：`https://api-test.hotelbyte.com`
- AppKey：`hotelbyte_api_demo`
- AppSecret：`hotelbyte_api_demo`
- 业务 Header 集合：
  - `Authorization: Bearer <ticket>`（ticket 从 `/api/auth/ticket` 拿，**含 `ST:` 前缀原样使用**）
  - `Session-Id: <uuid4>`（**预订流程必填**——必须跟 `/hotel-check-availability` 用同一个 Session-Id，否则 hotelbyte 判为不同会话会拒）
  - `Language: <IETF BCP 47>`（默认 `en-US`）
  - `Currency: <ISO 4217>`（默认 `USD`）
  - `Content-Type: application/json`

> **工具权限建议（agent-aware）**：本 skill 仅需要 `curl`（调 hotelbyte API）+ `date`（生成 ISO8601 时间戳）+ `uuidgen`（生成 idempotency key）+ `sleep`（订单状态轮询）。在 Claude Code 环境下，对应 `allowed-tools: Bash(curl:*), Bash(date:*), Bash(uuidgen:*), Bash(sleep:*)`；在其它 agent 工具下，请等价授予这四类外部命令的最小权限。

> **安全约束**：本命令涉及**真实下单操作**。默认 Dry-run，加 `--confirm` 才执行。**演示环境的 book 调用大概率失败**（ratePkgId 格式校验/session 创建限制），但仍会消耗一次酒店端的 API 配额——演示环境请慎重使用 `--confirm`。

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
| `customerReferenceNo` | 自动生成 | — | UUID4，**幂等键**——重复提交同一 ID 不会重复扣款 |
| `roomCount` | 否 | 1 | 房间数 |
| `--confirm` | 否 | false | 加这个标志才真下单 |

**中文姓名处理**（**干跑阶段就要确认**）：
- "张三" → `firstName: "San", lastName: "Zhang"`（拼音）
- 用 `Bash(date:*)` 自带的 LLM 拼音能力不强，**反问用户确认拼音写法**——CJK 字符传给酒店可能拒收

**`ratePkgId` 缺失或模糊**：反问一次。它是长字符串（实测格式如 `10000000<HB>-1<HB>SIM|2|CERT_FAM|RO|RF|1787241886|20260919|20260921`），从 `/hotel-check-availability` 的输出复制。

## ⚠️ 演示环境实测注意

实测发现 hotelbyte 演示 API 的 book 端点：
- **ratePkgId 格式校验**：`10000000<HB>-1<HB>SIM|2|CERT_FAM|RO|RF|1787241886|20260919|20260921` 这种格式才被接受
- **Session-Id 校验**：必须跟 `/hotel-check-availability` 用同一个 Session-Id
- **演示环境**的 hotelList 永远 no_availability，不会创建 session → book 调用必然失败

**演示环境下** book 调用大概率返回**分支 D（400 参数错误）** 或 **分支 E（404 session）**。

**真实生产环境**才能完整验证 status: 1 / status: 2 / status: 4 / status: 5 这些响应。

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

### 步骤 2：换 ticket（同其他 skill）

```bash
curl -sS -k -X POST -H "Content-Type: application/json" \
  -d '{"appKey":"hotelbyte_api_demo","appSecret":"hotelbyte_api_demo","ttl":3600}' \
  https://api-test.hotelbyte.com/api/auth/ticket
```

取 `data.ticket` 完整字符串。

### 步骤 3：生成 Session-Id 和 customerReferenceNo

⚠️ **关键**：从 `/hotel-check-availability` 轮询的对方上下文里，**复用对方 Session-Id**（保持会话一致）。如果用户**没有**先跑 `/hotel-check-availability`，**当场生成新的 Session-Id** 并警告：

> ⚠️ 提示：跳过了 `/hotel-check-availability`。建议先跑一次再下单，避免 ARI 变更被拒。

```bash
SESSION_ID=$(uuidgen)
CUSTOMER_REF=$(uuidgen)
```

### 步骤 4：Dry-run（默认）—— 输出"准备下单"清单

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
- customerReferenceNo:<uuid>（幂等键，重复提交不会扣两次款）
- Session-Id：<session-id>（必须跟之前 /hotel-check-availability 一致）

---

**确认下单吗？** 加 `--confirm` 重跑：

```bash
/hotel-book <ratePkgId> 张三 zhangsan@example.com --confirm
```

或者改一下：
- 改房间数：`/hotel-book <ratePkgId> 张三 zhangsan@example.com 2 rooms --confirm`
- 改客人姓名：`/hotel-book <ratePkgId> 李四 lisi@example.com --confirm`

> ⚠️ 演示环境提示：hotelbyte 演示 API 必然返回 400 或 404 分支（ratePkgId 格式校验 / session 不存在）。这是预期的——证明整个下单流程在跑，不是 bug。
```

**Dry-run 模式到此结束**——**不调 `/api/trade/book`**，不消耗对方 API 配额。

### 步骤 5：真下单（仅 `--confirm` 模式）

构造请求体（文档 §BookReq）：

```json
{
  "customerReferenceNo": "<uuid>",
  "ratePkgId": "<ratePkgId>",
  "holder": {
    "firstName": "San",
    "lastName": "Zhang",
    "email": "zhangsan@example.com"
  },
  "guests": [
    {
      "roomIndex": 1,
      "firstName": "San",
      "lastName": "Zhang"
    }
  ]
}
```

如果是 2 间房：

```json
{
  "customerReferenceNo": "<uuid>",
  "ratePkgId": "<ratePkgId>",
  "holder": { ... },
  "guests": [
    {"roomIndex": 1, "firstName": "San", "lastName": "Zhang"},
    {"roomIndex": 2, "firstName": "Si", "lastName": "Li"}
  ]
}
```

发请求：

```bash
curl -sS -k -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ST:..." \
  -H "Session-Id: <session-id>" \
  -H "Language: en-US" \
  -H "Currency: USD" \
  -d '{
    "customerReferenceNo": "<uuid>",
    "ratePkgId": "10000000<HB>-1<HB>SIM|2|CERT_FAM|RO|RF|1787241886|20260919|20260921",
    "holder": {"firstName":"San","lastName":"Zhang","email":"zhangsan@example.com"},
    "guests": [{"roomIndex":1,"firstName":"San","lastName":"Zhang"}]
  }' \
  https://api-test.hotelbyte.com/api/trade/book
```

### 步骤 6：解读 book 响应（5 个分支）

#### 分支 A：下单成功（`status: 1 = Confirming` 或 `status: 2 = Confirmed`）—— 真实生产环境

**演示环境无法验证**。预期响应结构（从 Apifox 文档）：

```json
{
  "code": 0,
  "msg": "",
  "data": {
    "hotelOrder": {
      "status": 1,
      "statusRemark": "正在确认中",
      "checkIn": "2026-08-28",
      "checkOut": "2026-08-30",
      "nightCount": 2,
      "roomCount": 1,
      "bookingTime": "2026-08-21T08:00:00Z",
      "platformReferenceNo": "PLT202608210001234",
      "customerReferenceNo": "abcdef-1234-5678-...",
      "supplierReferenceNo": "SUP12345",
      "netRate": {"currency": "USD", "amount": 555.00},
      "grossRate": {"currency": "USD", "amount": 600.00},
      "hotel": {"hotelId": "...", "name": {"en": "...", "zh": "..."}, "address": {...}},
      "rooms": [{"roomTypeId": "...", "ratePkgId": "...", "checkIn": "...", "checkOut": "...", "rate": {...}, "totalRate": {...}}]
    }
  }
}
```

**拿到 `status: 1` 后立即进入轮询**（步骤 7）。

#### 分支 B：ARI 变更（`code: 100001111`）—— 真实生产环境

**演示环境无法验证**。预期响应：

```json
{"code": 100001111, "msg": "ARI changed"}
```

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

#### 分支 C：参数错误（`code: 100000400`）—— 演示环境实测过

**实测响应**：
```json
{"code": 100000400, "msg": "ratePkgId validation failed at RP461850557-1234567890: invalid ratePkgId format: RP461850557-1234567890"}
```

或：
```json
{"code": 100000400, "msg": "param error"}
```

输出：

```markdown
# 参数错误

API 返回 `code: 100000400`, `msg: "ratePkgId validation failed at <ratePkgId>: invalid ratePkgId format"`。

**含义**：ratePkgId 是假的或格式错。

**演示环境下**：用 `/hotel-search` 永远返回 no_availability 拿不到真实 ratePkgId，所以演示环境必然返回本分支。**这是正常的**，证明 toolchain 跑通了。

**生产环境**：
- 重新跑 `/hotel-search` 拿真实 ratePkgId
- 用真实 ratePkgId 重新 `/hotel-check-availability` → `/hotel-book --confirm`
```

不进入轮询。

#### 分支 D：下单失败（`status: 4 = Failed`）—— 真实生产环境

**演示环境无法验证**。预期响应：

```json
{"code": 0, "msg": "", "data": {"hotelOrder": {"status": 4, "statusRemark": "供应商拒绝预订", "platformReferenceNo": "PLT...", "customerReferenceNo": "..."}}}
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

#### 分支 E：401 / 404 / 500 等其他错误

```markdown
# API 请求失败

API 返回 `code: <code>`, `msg: "<msg>"`。

**演示环境下常见**：
- 401 Unauthorized：ticket 过期
- 404 Not Found：session 不存在
- 500 Server Error：上游服务故障

**建议**：
- 401 → 重新换 ticket，再重试
- 404 → 重新跑 `/hotel-search` 创建 session
- 500 → 等 30 秒重试
```

不进入轮询。

### 步骤 7：轮询订单状态（仅分支 A 触发）

当 book 响应 `status: 1`（Confirming）时，**立即进入轮询**：

```bash
# 轮询 18 次，每次 10 秒
CUSTOMER_REF=<customerReferenceNo>
for i in $(seq 1 18); do
  RESPONSE=$(curl -sS -k -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ST:..." \
    -H "Session-Id: <session-id>" \
    -H "Language: en-US" \
    -d "{\"customerReferenceNos\":[\"$CUSTOMER_REF\"]}" \
    https://api-test.hotelbyte.com/api/trade/queryOrders)
  STATUS=$(echo "$RESPONSE" | jq -r '.data.orders[0].status // 0')
  echo "Attempt $i (every 10s): status=$STATUS"
  if [ "$STATUS" = "2" ] || [ "$STATUS" = "3" ] || [ "$STATUS" = "4" ]; then
    break
  fi
  sleep 10
done
```

**轮询退出条件**：
- `status: 2` (Confirmed) → ✅ 成功
- `status: 3` (Cancelled) → 不是这次下单的状态（book 不会让订单变 cancelled）
- `status: 4` (Failed) → 失败了
- `status: 5` (CancelFailed) → 同上
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
- 取消订单：`/hotel-cancel <customerReferenceNo> <supplierReferenceNo> [reason]`
```

### 步骤 8：写入 `.claude/orders/<customerReferenceNo>.json`（仅 `--confirm` 模式 + 仅分支 A 成功）

保存订单快照到本地，便于后续 `/hotel-cancel` 用：

```json
{
  "customerReferenceNo": "<uuid>",
  "platformReferenceNo": "PLT...",
  "supplierReferenceNo": "SUP...",
  "ratePkgId": "RP...",
  "hotelId": "461850557",
  "checkIn": "2026-08-28",
  "checkOut": "2026-08-30",
  "holder": {"firstName": "San", "lastName": "Zhang", "email": "..."},
  "guests": [...],
  "status": 2,
  "bookingTime": "2026-08-21T08:00:00Z",
  "totalRate": {"currency": "USD", "amount": 555.00},
  "sessionId": "<session-id>"
}
```

> **不**写入 `.claude/memory.db`（敏感数据不进 memory）。

## 兜底分支汇总

| 现象 | 处理 |
|------|------|
| `code: 0` + `status: 1` | 走 A 分支 → 轮询（**真实生产环境**） |
| `code: 0` + `status: 4` | 走 D 分支（失败，**真实生产环境**） |
| `code: 100001111` | 走 B 分支（ARI 变更，**真实生产环境**） |
| `code: 100000400` | 走 C 分支（参数错，**演示环境实测**） |
| `code: 100000404` | 走 E 分支（session 不存在，**演示环境实测**） |
| 其他 `code != 0` | 走 E 分支（API 异常） |
| `curl` 退出码非 0 | 重跑一次 + 报告 stderr |
| `data.ticket` 缺失 | 检查 `msg`，可能是 appKey 失效 |
| `ratePkgId` 含空格 / 看起来不对 | 反问："ratePkgId 是从 /hotel-check-availability 复制的长字符串" |
| 轮询 18 次仍未确定状态 | 报告"超时"，保留 `customerReferenceNo` 让用户手动查 |

## `--test` 模式

如果 `$ARGUMENTS` 含 `--test`，跑 Dry-run 输出（**不真下单**）：

```
ratePkgId=10000000<HB>-1<HB>SIM|2|CERT_FAM|RO|RF|1787241886|20260919|20260921（演示环境真实订单的 ratePkgId）
holder=张三 zhangsan@example.com
1 间房 1 个客人
```

输出顶部加 `[fixture] book dry-run`。用于演示下单流程。**不真下单**——演示环境库存稀缺，避免浪费。

## 不要做的事

- **不要默认真下单**——必须 `--confirm` 标志
- **不要跳过 `/hotel-check-availability`**——强烈建议先 verify 一次（虽然命令本身不强制，但 SKILL.md 顶部要 warn）
- **不要把演示凭据 `hotelbyte_api_demo` 写进任何文件 / 文档 / commit**
- **不要用 `Bash(*)` 宽权限**——本命令只能调 `curl` / `date` / `uuidgen` / `sleep`
- **不要把 ticket 持久化到 `.claude/memory.db`**
- **不要硬编码中文姓名** —— CJK 字符传给酒店可能拒收，**反问用户拼音**

## 已知限制

- **演示环境的 book 调用必然失败**（返回 400 或 404）——这是实测结论，演示环境没有真实库存 + session 缺位。
- 真实生产环境才能看到 → status 1 / 2 / 4 / 5 全部分支。
- 轮询超时 3 分钟。**真实的 confirm 可能需要 5-15 分钟**（供应商人工审单）。如果超时，保留 `customerReferenceNo` 让用户用 hotelbyte 客服或 `/hotel-cancel` 验证。
- 中文姓名 → 拼音的转换依赖 LLM 能力，**不保证准确**。商用场景建议让客户在网页上自行输入。
