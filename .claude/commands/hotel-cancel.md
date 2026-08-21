---
name: hotel-cancel
description: 取消已预订订单。默认 Dry-run（输出准备取消清单），加 --confirm 才真取消并轮询订单状态。/hotel-book 之后调用。
allowed-tools: Bash(curl:*), Bash(date:*), Bash(uuidgen:*) , Bash(sleep:*)
---

# /hotel-cancel

取消已预订的酒店订单。**默认 Dry-run 模式**——先调 `/api/trade/queryOrders` 查订单状态，输出"准备取消"清单让你确认；加 `--confirm` 才真取消、调 `/api/trade/cancel`、并轮询验证状态变更。

## API 配置

- 端点：`/api/trade/cancel`（取消）+ `/api/trade/queryOrders`（查订单）
- Base URL：`https://api-test.hotelbyte.com`
- AppKey：`hotelbyte_api_demo`
- AppSecret：`hotelbyte_api_demo`
- 业务 Header 集合：
  - `Authorization: Bearer <ticket>`（ticket 从 `/api/auth/ticket` 拿，**含 `ST:` 前缀原样使用**）
  - `Session-Id: <uuid4>`（**预订流程必填**——必须跟 `/hotel-book` 用同一个 Session-Id，便于酒店侧关联此次取消与原订单）
  - `Language: <IETF BCP 47>`（默认 `en-US`）
  - `Currency: <ISO 4217>`（默认 `USD`）
  - `Content-Type: application/json`

> **本机环境提示**：ZCode 自带 WebFetch 工具证书过期，无法直连 hotelbyte。本命令用 `curl`（Windows Schannel TLS 兼容），`allowed-tools` 已限定 `Bash(curl:*)` 和 `Bash(sleep:*)`（用于轮询）。

> **安全约束**：本命令涉及**真实取消订单操作**。默认 Dry-run，加 `--confirm` 才执行。**取消订单通常不可逆**（尤其是 status: 2 已确认的状态），演示环境请慎重使用 `--confirm`。

## 用户输入

```
$ARGUMENTS
```

支持的形态（Dry-run）：
- `/hotel-cancel <customerReferenceNo> <supplierReferenceNo>` —— 基础用法
- `/hotel-cancel <customerReferenceNo> <supplierReferenceNo> 客户临时取消` —— 加取消原因
- `/hotel-cancel <customerReferenceNo> <supplierReferenceNo> --all` —— 同时取消同一 supplierReferenceNo 下所有订单

真取消（加 `--confirm`）：
- `/hotel-cancel <customerReferenceNo> <supplierReferenceNo> --confirm`
- `/hotel-cancel <customerReferenceNo> <supplierReferenceNo> 客户临时取消 --confirm`

测试模式：
- `/hotel-cancel --test` —— 用固定 fixture 跑 Dry-run 输出

## 字段说明

| 字段 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `customerReferenceNo` | 是 | — | **从 `/hotel-book` 输出或 `.claude/orders/<uuid>.json` 拿**——这是我们生成的 |
| `supplierReferenceNo` | 是 | — | **从 `/hotel-book` 输出或 `.claude/orders/<uuid>.json` 拿**——这是酒店分配的 |
| `reason` | 否 | "Customer request" | 取消原因（10-200 字） |
| `--confirm` | 否 | false | 加这个标志才真取消 |
| `--all` | 否 | false | 取消同一 supplierReferenceNo 下所有订单 |

**两者都缺失或模糊**：反问一次，告诉用户从 `/hotel-book` 输出的"订单详情"复制。

## 状态机（文档 §OrderStatus）

| 值 | 名称 | 含义 | 可取消？ |
|---|---|---|---|
| 0 | Unknown | 未知（不应该出现） | ❌ |
| 1 | Confirming | 等待供应商确认 | ✅（趁还没确认） |
| 2 | Confirmed | 已确认 | ✅（**可能要付取消费**） |
| 3 | Cancelled | 已取消 | ❌（幂等，跳过） |
| 4 | Failed | 失败 | ❌（终态） |
| 5 | CancelFailed | 取消失败 | ⚠️（要查原因重试） |

## 流程

### 步骤 1：解析自然语言

解析 `$ARGUMENTS` 得到：
- `customerReferenceNo`
- `supplierReferenceNo`
- `reason`
- 是否有 `--confirm` / `--all` 标志

如果 `customerReferenceNo` 缺失：反问。
如果 `supplierReferenceNo` 缺失：反问。

### 步骤 2：换 ticket（同其他 skill）

```bash
curl -sS -k -X POST -H "Content-Type: application/json" \
  -d '{"appKey":"hotelbyte_api_demo","appSecret":"hotelbyte_api_demo","ttl":3600}' \
  https://api-test.hotelbyte.com/api/auth/ticket
```

取 `data.ticket` 完整字符串。

### 步骤 3：先 queryOrders 查订单状态（无论 Dry-run 还是 confirm）

⚠️ **关键**：在调 `/api/trade/cancel` 之前**先查订单状态**，避免：
- 取消已取消的订单（status: 3）
- 取消失败的订单（status: 4）
- 取消未知状态的订单（status: 0）

```bash
curl -sS -k -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ST:..." \
  -H "Session-Id: <session-id>"（建议从 `.claude/orders/<uuid>.json` 拿）
  -H "Language: en-US" \
  -d '{"customerReferenceNos":["<customerReferenceNo>"]}' \
  https://api-test.hotelbyte.com/api/trade/queryOrders
```

**解读状态**：

| 状态 | 处理 |
|---|---|
| 0 (Unknown) | 报错："订单不存在或未同步" |
| 1 (Confirming) | ✅ 可取消，且**无取消费**（订单还没正式确认） |
| 2 (Confirmed) | ✅ 可取消，但**可能有取消费**——查 `cancelFees` 给用户看 |
| 3 (Cancelled) | 跳过取消，报告"已取消" |
| 4 (Failed) | 跳过取消，报告"订单已失败" |
| 5 (CancelFailed) | 重试取消——把它当正常订单再 cancel 一次 |

### 步骤 4：Dry-run（默认）—— 输出"准备取消"清单

```markdown
# 🗑️ 准备取消（Dry-run，未执行）

**订单信息**（从 queryOrders 拿）：
- customerReferenceNo：<uuid>
- supplierReferenceNo：<id>
- platformReferenceNo：<id>
- 当前状态：<status>（<中文名>）
- checkIn：<date>
- checkOut：<date>
- 酒店：<name> (<address>)

**取消原因**：<reason>

**取消费估算**（仅 status 2 有）：
- 模式：<refundableMode: full/partial/no>
- 截止：<refundableUntil>
- 阶梯：
  - <until_1> 前取消：<fee_1> <currency>（通常 0 或很低）
  - <until_2> 前取消：<fee_2> <currency>
  - <until_3> 前取消：<fee_3> <currency>（临近入住）

**预计退款**：<refundable amount> <currency>（= 已付 - 取消费）

---

**确认取消吗？** 加 `--confirm` 重跑：

```bash
/hotel-cancel <customerReferenceNo> <supplierReferenceNo> --confirm
```

或者改一下：
- 改原因：`/hotel-cancel <customerReferenceNo> <supplierReferenceNo> 客户临时有事 --confirm`
```

**Dry-run 模式到此结束**——**不调 `/api/trade/cancel`**，不消耗对方 API 配额。

### 步骤 5：真取消（仅 `--confirm` 模式）

构造请求体（文档 §CancelReq）：

```json
{
  "customerReferenceNo": "<uuid>",
  "supplierReferenceNo": "<id>",
  "reason": "Customer request"
}
```

发请求：

```bash
curl -sS -k -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ST:..." \
  -H "Session-Id: <session-id>" \
  -H "Language: en-US" \
  -d '{
    "customerReferenceNo": "<uuid>",
    "supplierReferenceNo": "<id>",
    "reason": "Customer request"
  }' \
  https://api-test.hotelbyte.com/api/trade/cancel
```

### 步骤 6：解读 cancel 响应（3 个分支）

#### 分支 A：取消成功（`status: 3 = Cancelled`）

```json
{
  "code": 0,
  "msg": "",
  "data": {
    "serviceFee": {"currency": "USD", "amount": 0.00},
    "status": 3
  }
}
```

**拿到 `status: 3` 后立即进入轮询**（步骤 7）。

注意 `serviceFee` 是**供应商收的服务费**（不退还），customer 实际退款 = `totalRate - serviceFee`。

#### 分支 B：取消失败（`status: 5 = CancelFailed`）

```json
{
  "code": 0,
  "msg": "",
  "data": {
    "serviceFee": {"currency": "USD", "amount": 30.00},
    "status": 5
  }
}
```

输出：

```markdown
# ⚠️ 取消失败（status: 5）

**含义**：酒店已拒绝取消申请，可能原因：
- 已是免费取消截止日之后
- 酒店设置"不可取消"（status=2 但 refundableMode=no）
- 供应商系统故障

**服务费**：<serviceFee> <currency>（不退还）

**建议**：
- 立即用 `/hotel-cancel <customerReferenceNo> <supplierReferenceNo> --confirm` 重试（幂等）
- 或联系 hotelbyte 客服介入
- 或到酒店前台协调
```

**进入轮询**——可能需要 1-2 分钟供应商手工确认。

#### 分支 C：订单不存在（`code: 100000404`）

```json
{"code": 100000404, "msg": "not found"}
```

输出：

```markdown
# ❌ 订单不存在

API 返回 `code: 100000404`, `msg: "not found"`。

**可能原因**：
- `customerReferenceNo` 输错
- `supplierReferenceNo` 输错
- 订单在演示环境 24 小时后被清理

**建议**：
- 检查两个 ID 是否从 `/hotel-book` 输出复制
- 用 `/hotel-cancel --test` 跑 fixture 验证 toolchain
```

不进入轮询。

### 步骤 7：轮询订单状态（仅分支 A 或 B 触发）

轮询 `/api/trade/queryOrders`，看 `status` 是否变成 3：

```bash
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
  if [ "$STATUS" = "3" ]; then
    break
  fi
  if [ "$STATUS" = "5" ]; then
    echo "CancelFailed - 供应商拒绝取消"
    break
  fi
  sleep 10
done
```

**轮询退出条件**：
- `status: 3` → ✅ 取消成功
- `status: 5` → ❌ 取消失败（持久状态）
- 18 次都没动 → 还在处理中（罕见）

**轮询输出（分支 A 成功）**：

```markdown
# ✅ 取消完成

**订单状态变化**：
- 之前：<before_status>（<中文名>）
- 现在：<after_status>（<中文名>）

每次 10 秒，最多 18 次：

| 第 i 次 | status | 说明 |
|--------|--------|------|
| 1 | 3 (Cancelled) | ✅ 已取消 |

**退款详情**：
- 已付：<totalRate> <currency>
- 服务费（不退还）：<serviceFee> <currency>
- 实退：<refunded> <currency>
- 预计到账：3-10 个工作日

**订单 ID**：
- customerReferenceNo：<uuid>（永久保留）
- supplierReferenceNo：<id>
- platformReferenceNo：<id>

**下一步**：
- 重新预订：可以用同一个 Session-Id 跑 `/hotel-search`
- 修改订单：hotelbyte 测试 API 不支持 edit，只能"取消后重订"
```

### 步骤 8：更新 `.claude/orders/<customerReferenceNo>.json`

更新本地订单快照：

```json
{
  "customerReferenceNo": "<uuid>",
  "platformReferenceNo": "PLT...",
  "supplierReferenceNo": "SUP...",
  "...": "...",
  "status": 3,
  "cancelTime": "2026-08-21T08:00:00Z",
  "cancelReason": "Customer request",
  "serviceFee": {"currency": "USD", "amount": 0.00},
  "refundedPrice": {"currency": "USD", "amount": 555.00}
}
```

> **不**写入 `.claude/memory.db`（敏感数据不进 memory）。

## 兜底分支汇总

| 现象 | 处理 |
|------|------|
| `code: 0` + `status: 3` | 走 A 分支 → 轮询 |
| `code: 0` + `status: 5` | 走 B 分支（取消失败） |
| `code: 100000404` | 走 C 分支（订单不存在） |
| 其他 `code != 0` | 走 E 分支（API 异常） |
| 查询返回空数组 | 走 C 分支（订单不存在） |
| `curl` 退出码非 0 | 重跑一次 + 报告 stderr |
| `data.ticket` 缺失 | 检查 `msg`，可能是 appKey 失效 |
| 两个 ID 看起来不对 | 反问："两个 ID 都是从 /hotel-book 输出的详情复制" |
| 轮询 18 次仍未变 3 | 报告"取消进行中"，保留 ID 让用户重试 |

## `--test` 模式

如果 `$ARGUMENTS` 含 `--test`，跑 Dry-run 输出（**不真取消**）：

```
customerReferenceNo=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx（生成的随机 UUID）
supplierReferenceNo=SUP12345（文档示例）
reason="Customer request"
```

输出顶部加 `[fixture] cancel dry-run`。用于演示取消流程。**不真取消**——演示环境库存稀缺，避免浪费。

## 不要做的事

- **不要默认真取消**——必须 `--confirm` 标志
- **不要跳过 queryOrders**——一定要先查订单状态确认可取消
- **不要把演示凭据 `hotelbyte_api_demo` 写进任何文件 / 文档 / commit**
- **不要用 `Bash(*)` 宽权限**——本命令只能调 `curl` / `date` / `uuidgen` / `sleep`
- **不要把 ticket 持久化到 `.claude/memory.db`**
- **不要取消后再取消**——queryOrders 检查 status 3 等终态，跳过重复取消

## 已知限制

- 演示环境的取消通常对 status 2 (Confirmed) 订单有效，对 status 1 (Confirming) 也能取消（demo 几乎不会走到 status 2 因为库存稀缺）。
- 取消是**不可逆**操作。**真实订单一旦确认取消，款项会进入退款流程（3-10 工作日）**。
- 不支持"修改订单"（改日期、改房型）。如需这类操作，必须"取消后重订"，损失取消费。
- 不支持"部分取消"（只取消订单的 1 间房）。一个订单要么全取消，要么不取消。
