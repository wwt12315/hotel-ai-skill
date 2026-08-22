---
name: hotel-cancel
description: "通过 hbcli 取消已预订订单。默认 Dry-run（输出准备取消清单），加 --confirm 才真取消并轮询订单状态。在 hotel-book 之后调用。触发词包括『取消订单』『取消预订』『cancel booking』『cancel order』。演示环境为 api-test.hotelbyte.com。"
---

# /hotel-cancel

通过 `hbcli` 取消已预订的酒店订单。**默认 Dry-run 模式**——先调 `/api/trade/queryOrders` 查订单状态，输出"准备取消"清单让你确认；加 `--confirm` 才真取消、调 `/api/trade/cancel`、并轮询验证状态变更。

## 前提条件

> 本 skill 假设 `hbcli` 已经安装并配好凭据。如未安装：

```bash
curl -fsSL https://github.com/hotelbyte-com/docs/releases/latest/download/install.sh | bash
hbcli auth set-credentials \
  --app-key hotelbyte_api_demo \
  --app-secret hotelbyte_api_demo
```

`hbcli` 自带 ticket 管理 + Session-Id 管理。

> **安全约束**：本命令涉及**真实取消订单操作**。默认 Dry-run，加 `--confirm` 才执行。**取消订单通常不可逆**（尤其是 status: 2 已确认的状态），演示环境请慎重使用 `--confirm`。

## 用户输入

```
$ARGUMENTS
```

支持的形态（Dry-run）：
- `/hotel-cancel <customerReferenceNo> <supplierReferenceNo>` —— 基础用法
- `/hotel-cancel <customerReferenceNo> <supplierReferenceNo> 客户临时取消` —— 加取消原因

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

## ⚠️ 演示环境实测注意

实测发现 hotelbyte 演示 API 的 cancel / queryOrders 端点：

- **`queryOrders` 空请求** `{}` 会返回**演示环境所有订单**（用于发现演示订单 ID）
- **`queryOrders` 指定不存在的 customerReferenceNo**返回 `{"code": 0, "data": {"orders": []}}`
- **`cancel` 调用**会先调 queryOrders 找订单，找不到直接返回 `{"code": 100000404, "msg": "failed to query order"}`

**演示环境下**本命令的预期行为：
- Dry-run 必定返回"订单不存在"或"已取消"（演示环境没有真实活动订单）
- 真取消 `--confirm` 必然返回分支 C（404）

**演示环境内唯一真实的订单**（用 `queryOrders` `{}` 实测发现的）：
- `customerReferenceNo`: `E2E_TEST_1a05121d-77f4-4751-90a5-c09eb5e01138`
- `supplierReferenceNo`: `71705286443857226`
- `platformReferenceNo`: `71705286443857226`
- `status`: 3（Cancelled）—— 已取消的订单，**不能再取消**（幂等）

**真实生产环境**才能完整验证 status: 1 / 2 / 4 / 5 这些响应。

### 2026-08-21 重测补充：queryOrders 过滤字段实测

实测 queryOrders 的 4 种 filter body 形态（`hbcli` 已自动包成 `--customer-reference-nos` / `--supplier-reference-nos` 复数 + 数组形式）：

| CLI 参数 | 演示环境响应（HTTP 200, code:0） | 解读 |
|---|---|---|
| `{}`（不传过滤） | `orders[]` 含全部 100 条 demo 订单（251 KB） | 不过滤 |
| `--customer-reference-nos "E2E_TEST_..."` | `orders[]` 含 1 条匹配订单（2.5 KB） | **过滤生效** ✓ |
| `--customer-reference-nos "FAKE-..."` | `orders[]` 空数组（40 B） | 过滤生效，无匹配 |
| `--supplier-reference-nos "71705286443857226"` | `orders[]` 含 1 条匹配订单（2.5 KB） | **过滤生效** ✓ |

**结论**：
- `hbcli trade query-orders` 的 `--customer-reference-nos` 和 `--supplier-reference-nos`（**复数 + 数组**）都生效
- 本 SKILL.md 步骤 3 用的是 `--customer-reference-nos`（复数），符合 hotelbyte 规范
- 想用 supplier 维度过滤时务必用 `--supplier-reference-nos`（复数）

## 流程

### 步骤 1：解析自然语言

解析 `$ARGUMENTS` 得到：
- `customerReferenceNo`
- `supplierReferenceNo`
- `reason`
- 是否有 `--confirm` 标志

如果 `customerReferenceNo` 缺失：反问。
如果 `supplierReferenceNo` 缺失：反问。

### 步骤 2：先 queryOrders 查订单状态（无论 Dry-run 还是 confirm）

⚠️ **关键**：在调 `/api/trade/cancel` 之前**先查订单状态**，避免：
- 取消已取消的订单（status: 3）
- 取消失败的订单（status: 4）
- 取消未知状态的订单（status: 0）

```bash
hbcli --json trade query-orders \
  --customer-reference-nos "<customerReferenceNo>"
```

**解读状态**（实测分支）：

| 状态 | 处理 |
|---|---|
| 0 (Unknown) | 报错："订单不存在或未同步" |
| 1 (Confirming) | ✅ 可取消，且**无取消费**（订单还没正式确认） |
| 2 (Confirmed) | ✅ 可取消，但**可能有取消费**——查 `cancelFees` 给用户看 |
| 3 (Cancelled) | 跳过取消，报告"已取消" |
| 4 (Failed) | 跳过取消，报告"订单已失败" |
| 5 (CancelFailed) | 重试取消——把它当正常订单再 cancel 一次 |

**实测响应**：
- 订单存在：`{"ok": true, "status": 200, "body": {"code": 0, "msg": "", "data": {"orders": [<订单>...]}}}`
- 订单不存在：`{"ok": true, "status": 200, "body": {"code": 0, "msg": "", "data": {"orders": []}}}`
- 空请求 `{}` 会返回演示环境所有订单

### 步骤 3：Dry-run（默认）—— 输出"准备取消"清单

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

### 步骤 4：真取消（仅 `--confirm` 模式）

构造请求体（文档 §CancelReq）：

```json
{
  "customerReferenceNo": "<uuid>",
  "supplierReferenceNo": "<id>",
  "reason": "Customer request"
}
```

调 `hbcli`：

```bash
hbcli --json trade cancel \
  --customer-reference-no "<customerReferenceNo>" \
  --supplier-reference-no "<supplierReferenceNo>" \
  --reason "Customer request"
```

### 步骤 5：解读 cancel 响应（4 个分支）

`hbcli --json` 把 HTTP 响应包成 `{ok, status, body}` 三段。

#### 分支 A：取消成功（`status: 3 = Cancelled`）—— 真实生产环境

**演示环境无法验证**。预期响应：

```json
{
  "ok": true,
  "status": 200,
  "body": {
    "code": 0,
    "msg": "",
    "data": {
      "serviceFee": {"currency": "USD", "amount": 0.00},
      "status": 3
    }
  }
}
```

**拿到 `status: 3` 后立即进入轮询**（步骤 6）。

注意 `serviceFee` 是**供应商收的服务费**（不退还），customer 实际退款 = `totalRate - serviceFee`。

#### 分支 B：取消失败（`status: 5 = CancelFailed`）—— 真实生产环境

**演示环境无法验证**。预期响应：

```json
{
  "ok": true,
  "status": 200,
  "body": {
    "code": 0,
    "msg": "",
    "data": {
      "serviceFee": {"currency": "USD", "amount": 30.00},
      "status": 5
    }
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

#### 分支 C：订单不存在（`code: 100000404`）—— **演示环境实测**

**实测响应**（随便给一个不存在的 customerReferenceNo）：

```json
{"ok": false, "status": 404, "error": "{\"code\": 100000404, \"msg\": \"failed to query order\"}"}
```

**含义**：cancel 内部先 queryOrders 找订单，找不到就返回 404。

输出：

```markdown
# ❌ 订单不存在

API 返回 `code: 100000404`, `msg: "failed to query order"`。

**可能原因**：
- `customerReferenceNo` 输错
- `supplierReferenceNo` 输错
- 订单在演示环境已经被清理
- 演示环境没有真实活动订单

**演示环境 fallback**：
- 用 `queryOrders` 发空请求 `{}` 可以获取演示环境所有订单
- 演示环境内唯一真实订单（已取消状态 3）：
  - customerReferenceNo: `E2E_TEST_1a05121d-77f4-4751-90a5-c09eb5e01138`
  - supplierReferenceNo: `71705286443857226`
  - 状态：3 (Cancelled) —— 取消幂等会跳过

**建议**：
- 检查两个 ID 是否从 `/hotel-book` 输出复制
- 用 `/hotel-cancel --test` 跑 fixture 验证 toolchain
- 在生产环境或已有真实订单的环境跑
```

不进入轮询。

#### 分支 D：参数错误（`code: 100000400`）—— 演示环境实测

**实测响应**（customerReferenceNo 和 supplierReferenceNo 都缺失）：

```json
{"ok": false, "status": 400, "error": "{\"code\": 100000400, \"msg\": \"order identifier is required\"}"}
```

**含义**：cancel 强制要求至少一个订单标识。

输出：

```markdown
# 参数错误

API 返回 `code: 100000400`, `msg: "order identifier is required"`。

**含义**：customerReferenceNo 和 supplierReferenceNo 都缺失。

**建议**：
- 提供 customerReferenceNo（从 /hotel-book 输出复制）
- 或提供 supplierReferenceNo（同上）
```

不进入轮询。

### 步骤 6：轮询订单状态（仅分支 A 或 B 触发）

轮询 `/api/trade/queryOrders`，看 `status` 是否变成 3：

```bash
CUSTOMER_REF=<customerReferenceNo>
for i in $(seq 1 18); do
  RESPONSE=$(hbcli --json trade query-orders \
    --customer-reference-nos "$CUSTOMER_REF")
  STATUS=$(echo "$RESPONSE" | jq -r '.body.data.orders[0].status // 0')
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

### 步骤 7：更新 `.claude/orders/<customerReferenceNo>.json`（仅分支 A 或 B 成功）

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
| `body.code: 0` + `status: 3` | 走 A 分支 → 轮询（**真实生产环境**） |
| `body.code: 0` + `status: 5` | 走 B 分支（取消失败，**真实生产环境**） |
| `body.code: 100000404` + msg "failed to query order" | 走 C 分支（订单不存在，**演示环境实测**） |
| `body.code: 100000400` + msg "order identifier is required" | 走 D 分支（参数错，**演示环境实测**） |
| `body.data.orders` 空数组 | 走 C 分支（订单不存在） |
| 其他 `body.code != 0` | 走 E 分支（API 异常） |
| `hbcli ok == false` | 走 E 分支（HTTP 4xx/5xx） |
| `hbcli` 退出码非 0 | 重跑一次 + 报告 stderr |
| 两个 ID 看起来不对 | 反问："两个 ID 都是从 /hotel-book 输出的详情复制" |
| 轮询 18 次仍未变 3 | 报告"取消进行中"，保留 ID 让用户重试 |

## `--test` 模式

如果 `$ARGUMENTS` 含 `--test`，跑 Dry-run 输出（**不真取消**）：

```
customerReferenceNo=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx（生成的随机 UUID，演示环境必然找不到）
supplierReferenceNo=SUP12345（文档示例）
reason="Customer request"
```

**演示环境下**：预期返回**分支 C（404）**——这是正常的，证明 toolchain 通了。

输出顶部加 `[fixture] cancel dry-run`。用于演示取消流程。

## 不要做的事

- **不要默认真取消**——必须 `--confirm` 标志
- **不要跳过 queryOrders**——一定要先查订单状态确认可取消
- **不要把演示凭据 `hotelbyte_api_demo` 写进任何文件 / 文档 / commit**
- **不要用 `Bash(*)` 宽权限**——本命令只能调 `hbcli` + `sleep`
- **不要取消后再取消**——queryOrders 检查 status 3 等终态，跳过重复取消

## 已知限制

- **演示环境的 cancel 必然失败**（返回 404 或 400）——演示环境没有真实活动订单。
- 真实生产环境才能看到 → status 1 / 2 / 4 / 5 全部分支。
- 取消是**不可逆**操作。**真实订单一旦确认取消，款项会进入退款流程（3-10 工作日）**。
- 不支持"修改订单"（改日期、改房型）。如需这类操作，必须"取消后重订"，损失取消费。
- 不支持"部分取消"（只取消订单的 1 间房）。一个订单要么全取消，要么不取消。