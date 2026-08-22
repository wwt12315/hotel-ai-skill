---
name: hotel-check-availability
description: "在 hotel-search 之后、hotel-book 之前调用。通过 hbcli 验证某个 ratePkgId 当前是否可订、价格是否变化、库存是否仍在。hotelbyte 文档明确要求『verify before commit』，跳过此步直接下单可能因 ARI 变更被拒。触发词包括『验证可订性』『check availability』『verify before book』。演示环境为 api-test.hotelbyte.com。"
---

# /hotel-check-availability

在 `/hotel-search` 拿到 `ratePkgId` 之后、下单之前跑一次。hotelbyte 文档明确要求"verify before commit"——价格和库存可能在你查询后的几秒内变动，跳过此步直接下单可能被拒。

## 前提条件

> 本 skill 假设 `hbcli` 已经安装并配好凭据。如未安装，请先执行：

```bash
curl -fsSL https://github.com/hotelbyte-com/docs/releases/latest/download/install.sh | bash
hbcli auth set-credentials \
  --app-key hotelbyte_api_demo \
  --app-secret hotelbyte_api_demo
```

`hbcli` 自带 ticket 管理，agent 不需要手动换 token / 维护 Session-Id。

## 用户输入

```
$ARGUMENTS
```

支持的形态：
- `/hotel-check-availability <ratePkgId>` —— 基础用法
- `/hotel-check-availability --test` —— 用固定 fixture 回归

## 字段说明

| 字段 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `ratePkgId` | 是 | — | 必须从 `/hotel-search` 响应里 `data.list[].rooms[].rates[].ratePkgId` 拿 |

**`ratePkgId` 缺失或模糊**：反问一次。它是长字符串（实测格式如 `10000000<HB>-1<HB>SIM|2|CERT_FAM|RO|RF|1787241886|20260919|20260921`），从 `/hotel-search` 输出的"报价 ID"列复制。

## ⚠️ 演示环境实测注意

实测发现 hotelbyte 演示 API 的 session 机制：
- `checkAvail` 端点会**校验 Session-Id**对应的 internal session 是否存在
- 演示环境的 `hotelList` 永远返回 `no_availability`—— 它**不创建 session**
- 所以**演示环境下**用 `checkAvail` 会报 `code: 100000404, msg: "session not found..."`

**真实生产**或**有库存环境**才能完整验证本端点。演示环境能验证的只有：
- 错误分支（ratePkgId 格式错、空参数、Session-Id 不存在）
- 不会验证到 status: 1 / status: 2 的真实响应

## 流程

### 步骤 1：调用 `hbcli search check-avail`

```bash
hbcli --json search check-avail --rate-pkg-id "<ratePkgId>"
```

### 步骤 2：解读响应（5 个分支）

`hbcli --json` 把 HTTP 响应包成 `{ok, status, body}` 三段。

#### 分支 A：可订（`status: 1`）—— 真实生产环境的最佳情况

**演示环境无法验证**。预期响应结构：

```json
{
  "ok": true,
  "status": 200,
  "body": {
    "code": 0,
    "msg": "",
    "data": {
      "status": 1,
      "roomRatePkg": {
        "ratePkgId": "...",
        "refundableMode": "full",
        "refundableUntil": "2026-08-25T23:59:59Z",
        "rate": {"netRate": {...}, "commissionableRate": {...}, "grossRate": {...}},
        "totalRate": {"netRate": {...}, "commissionableRate": {...}, "grossRate": {...}},
        "checkIn": "2026-08-28",
        "checkOut": "2026-08-30",
        "board": {"boardId": "BB", "boardName": "Bed & Breakfast"},
        "tax": {"total": {...}},
        "cancelFees": [{"until": "...", "fee": {...}}]
      },
      "exchangeRateSnapshot": {"date": "...", "usd": {...}}
    }
  }
}
```

输出：

```markdown
# ✅ 可订：<ratePkgId>

**价格**（snapshot 时点）：
- 单价：<netRate> / <commissionableRate> / <grossRate>
- 总价：<totalRate>（多间多晚）
- 汇率快照：<exchangeRateSnapshot>

**取消政策**：
- 模式：<refundableMode: full/partial/no 翻译>
- 截止：<refundableUntil>
- 阶梯：<cancelFees 列表>

**餐食**：<board.boardId>（<board.boardName>）

**下一步**：✅ 确认无误，请用 `/hotel-book <ratePkgId> <FirstName> <LastName> <email> [--confirm]`

> 提示：snapshot 价格只在当前会话有效。如果你隔了 1 分钟才下单，**请重新跑一次** `/hotel-check-availability`。
```

#### 分支 B：不可订（`status: 2`）—— 真实生产环境的常见情况

**演示环境无法验证**。预期响应：

```json
{"ok": true, "status": 200, "body": {"code": 0, "msg": "", "data": {"status": 2}}}
```

输出：

```markdown
# ❌ 不可订：<ratePkgId>

**库存状态**：不可订（status: 2）

**可能原因**：
- 这 1-2 秒内被其他用户抢走了
- 演示环境的库存是抢手资源
- 供应商主动下架

**建议**：
- 重新跑 `/hotel-search` 拿新的 ratePkgId
- 选另一个房型或酒店
```

#### 分支 C：ARI 变更（`code: 100001111`）—— 真实生产环境的常见情况

**演示环境无法验证**。预期响应：

```json
{"ok": false, "status": 409, "error": "{\"code\": 100001111, \"msg\": \"ARI changed\"}"}
```

输出：

```markdown
# ⚠️ 价格/库存已变更：<ratePkgId>

API 返回 `code: 100001111`, `msg: "ARI changed"`。

**含义**：Availability / Rates / Inventory 三个维度中至少一个变了。

**建议**：
- **强制重新跑** `/hotel-search` 拿最新 ratePkgId 和价格
- 对比新旧价格
- 如果用户接受 → 用新 ratePkgId 再跑 `/hotel-check-availability`
- 如果不接受 → 选别的房型
```

#### 分支 D：参数错误（`code: 100000400`）—— 演示环境实测过

**实测响应**：

```json
{"ok": false, "status": 400, "error": "{\"code\": 100000400, \"msg\": \"ratePkgId validation failed: invalid ratePkgId format\"}"}
```

输出：

```markdown
# 参数错误

API 返回 `code: 100000400`, `msg: "param error"` 或 `msg: "ratePkgId validation failed: ..."`。

**可能原因**：
- ratePkgId 是假的（演示环境的真实 ratePkgId 必须是 `/hotel-search` 返回的格式）
- 语言/币种参数格式错

**建议**：
- 重新跑 `/hotel-search` 拿真实 ratePkgId
- 用 `/hotel-check-availability --test` 跑 fixture 看 toolchain 是否工作
```

#### 分支 E：Session-Id 不存在（`code: 100000404`）—— 演示环境**实测过**

**实测响应**：

```json
{"ok": false, "status": 404, "error": "{\"code\": 100000404, \"msg\": \"session not found for userSessionId ... (internal: s:1:...)\"}"}
```

输出：

```markdown
# ⚠️ Session 不存在

API 返回 `code: 100000404`, `msg: "session not found..."`。

**含义**：你的 `Session-Id` 没在 hotelbyte 内部 session 注册。

**根本原因**：
- hotelbyte 只有 `hotelList` 返回 `status: success` 才会创建 session
- 演示环境永远返回 `no_availability` —— 不会创建 session
- `checkAvail` 校验 session 找不到就报错

**演示环境下**：
- 本命令**必然**返回本分支
- 这是正常的，**不是 bug**，证明 toolchain 跟 API 通了

**生产环境**：
- 要先跑 `/hotel-search` 拿到 `status: success` 的真实酒店 → 内部 session 被创建
- 再用此时拿到的 ratePkgId 调 `/hotel-check-availability`

**建议**：
- 演示环境用 `/hotel-check-availability --test` 跑 fixture 验证 toolchain
- 真实下单演示环境不可行——请用生产 endpoint + 真实库存
```

#### 分支 F：API 异常 / 限流

```markdown
# API 请求失败

`hbcli` 返回 `ok: false` + `error`。
HTTP 状态码：<status>
响应：<前 500 字>

**建议**：
- 等 30 秒重试（429 限流）
- 验证 `ratePkgId` 是否正确（404 找不到）
```

## 跟其他 skill 的衔接

**`/hotel-search` → `/hotel-check-availability` → `/hotel-book`**

```
/hotel-search Tokyo ...
   ↓ 拿到 list[].rooms[].rates[].ratePkgId
/hotel-check-availability <ratePkgId>
   ↓ 分支 A：可订 → 给出 snapshot 价格
/hotel-book <ratePkgId> 张三 zhangsan@example.com --confirm
   ↓ 下单 + 轮询订单
```

**关键约束**：
- 从 `/hotel-check-availability` 拿到 snapshot 到 `/hotel-book` 调用，**应 < 60 秒**。超过 1 分钟重新 verify。
- `/hotel-check-availability` 跟 `/hotel-book` 由 `hbcli` 内部共用同一 session，agent 无需手动维护 Session-Id。

## 兜底分支汇总

| 现象 | 处理 |
|------|------|
| `body.data.status == 1` | 走 A 分支（可订）—— 真实生产环境 |
| `body.data.status == 2` | 走 B 分支（不可订）—— 真实生产环境 |
| `body.code == 100001111` | 走 C 分支（ARI 变更）—— 真实生产环境 |
| `body.code == 100000400` | 走 D 分支（参数错）—— **演示环境实测** |
| `body.code == 100000404` + msg 含 "session not found" | 走 E 分支（演示环境**必然**） |
| 其他 `body.code != 0` | 走 F 分支（API 异常） |
| `hbcli ok == false` | 走 F 分支（HTTP 4xx/5xx） |
| `hbcli` 退出码非 0 | 重跑一次 + 报告 stderr |
| `ratePkgId` 含空格 / 看起来不对 | 反问："ratePkgId 应是从 /hotel-search 复制的长字符串" |

## `--test` 模式

如果 `$ARGUMENTS` 含 `--test`，跑固定 fixture：

```
ratePkgId=10000000<HB>-1<HB>SIM|2|CERT_FAM|RO|RF|1787241886|20260919|20260921（演示环境真实订单的 ratePkgId）
```

**演示环境下**：预期返回分支 E（session not found）或分支 D（参数错）。**这是正常的**——证明 toolchain 通了。

**生产环境**：会返回分支 A（可订）或 B（不可订）。

输出顶部加 `[fixture] check availability`。用于 toolchain 验证。

## 不要做的事

- 不要跳过本 skill 直接 `/hotel-book`——hotelbyte 文档明确要求 verify-before-commit
- 不要把 snapshot 价格当成"永恒价格"——> 60 秒就要重新 verify
- 不要把演示凭据 `hotelbyte_api_demo` 写进任何文件 / 文档 / commit
- 不要用 `Bash(*)` 宽权限——本命令只能调 `hbcli`
- 不要瞎编 `ratePkgId` —— 真实 ID 只能从 `/hotel-search` 响应拿