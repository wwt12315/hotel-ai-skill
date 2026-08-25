---
name: hotel-check-availability
description: "在 hotel-search 之后、hotel-book 之前调用。通过 curl 验证某个 ratePkgId 当前是否可订、价格是否变化、库存是否仍在。hotelbyte 文档明确要求『verify before commit』，跳过此步直接下单可能因 ARI 变更被拒。触发词包括『验证可订性』『check availability』『verify before book』。演示环境为 api-test.hotelbyte.com。"
---

# /hotel-check-availability

在 `/hotel-search` 拿到 `ratePkgId` 之后、下单之前跑一次。hotelbyte 文档明确要求"verify before commit"——价格和库存可能在你查询后的几秒内变动，跳过此步直接下单可能被拒。

## 前提条件

1. **工具**：`curl` + `jq`。Windows 用 Git Bash；macOS/Linux 直接用。
2. **凭据**：演示环境用 hotelbyte 公开 demo key。Agent 在每次调用前**用户自己 export**：

```bash
export HOTELBYTE_DEMO_APP_KEY="<your-hotelbyte-demo-app-key>"
export HOTELBYTE_DEMO_APP_SECRET="<your-hotelbyte-demo-app-secret>"
export HOTELBYTE_BASE_URL="https://api-test.hotelbyte.com"
```

> Demo 凭据从 hotelbyte 官方公开渠道获取；**agent 不允许 commit / 写进任何持久化文件**。本 SKILL.md 用 `${HOTELBYTE_DEMO_APP_KEY}` / `${HOTELBYTE_DEMO_APP_SECRET}` / `${HOTELBYTE_BASE_URL}` 占位。

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

**`ratePkgId` 缺失或模糊**：反问一次。它是长字符串（演示环境实测格式如 `10000000<HB>-1<HB>E2-NRF|20260924|20260926`），从 `/hotel-search` 输出的"报价 ID"列复制。

## ⚠️ 演示环境实测注意

实测发现 hotelbyte 演示 API 的 `checkAvail` 端点：

- **演示环境（`api-test.hotelbyte.com`）无论真假 ratePkgId 都返回 `code: 100000400 / msg: param error`** —— 2026-08-25 实测确认
- 这跟之前以为的"session not found / 100000404"不一样；演示环境现在返回的是 `param error`
- `param error` 不代表 ratePkgId 真的是错的，而是演示环境的 `checkAvail` 端点校验更严

**真实生产环境**才能完整验证 status: 1（可订）/ status: 2（不可订）的真实响应。演示环境能验证的只有：
- 错误分支（演示环境统一返回 `code: 100000400`）
- 不会验证到 status: 1 / status: 2 的真实响应

## 流程

### 步骤 1：拿 ticket

```bash
TICKET=$(curl -sS -X POST "${HOTELBYTE_BASE_URL}/api/auth/ticket" \
  -H "Content-Type: application/json" \
  -d "{\"appKey\":\"${HOTELBYTE_DEMO_APP_KEY}\",\"appSecret\":\"${HOTELBYTE_DEMO_APP_SECRET}\",\"ttl\":3600}" \
  | jq -er '.data.ticket')
```

### 步骤 2：调 checkAvail

```bash
CHECK=$(curl -sS -X POST "${HOTELBYTE_BASE_URL}/api/search/checkAvail" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TICKET" \
  -d "{\"ratePkgId\":\"$RATE_PKG_ID\"}")
```

### 步骤 3：解读响应（4 个分支）

**所有 hotelbyte 端点返回统一响应壳**：

```json
{ "code": 0, "msg": "Success", "data": { ... } }
```

#### 分支 A：可订（`code: 0 + data.status: 1`）—— 真实生产环境的最佳情况

**演示环境无法验证**（演示 checkAvail 必然走 C 分支）。预期响应：

```json
{
  "code": 0,
  "data": {
    "status": 1,
    "roomRatePkg": {
      "ratePkgId": "10000000<HB>-1<HB>E2-NRF|20260924|20260926",
      "refundableMode": "no",
      "board": {"boardId": "RO", "boardName": {"en": "Room Only"}},
      "rate": {"netRate": {"amount": "30.20", "currency": "USD"},
               "commissionableRate": {"amount": "33.22", "currency": "USD"},
               "grossRate": {"amount": "35.70", "currency": "USD"}},
      "totalRate": {"netRate": {"amount": "60.4", "currency": "USD"}, ...},
      "cancelFees": []
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

**取消政策**：
- 模式：<refundableMode: full/partial/no 翻译>
- 阶梯：<cancelFees 列表>

**餐食**：<board.boardId>（<board.boardName>）

**下一步**：✅ 确认无误，请用 `/hotel-book <ratePkgId> 张三 zhangsan@example.com [--confirm]`

> 提示：snapshot 价格只在当前会话有效。如果你隔了 1 分钟才下单，**请重新跑一次** `/hotel-check-availability`。
```

#### 分支 B：不可订（`code: 0 + data.status: 2`）—— 真实生产环境的常见情况

**演示环境无法验证**。预期响应：

```json
{"code": 0, "data": {"status": 2}}
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

#### 分支 C：参数错误（`code: 100000400`）—— **演示环境实测**

**实测响应**（2026-08-25，无论真假 ratePkgId 都返回这条）：

```json
{"code": 100000400, "msg": "param error"}
```

输出：

```markdown
# ⚠️ 参数错误 / 演示环境限制

API 返回 `code: 100000400`, `msg: "param error"`。

**含义**：hotelbyte API 拒绝该 ratePkgId 或参数。

**演示环境下**：
- 本命令**必然**返回本分支（演示环境的 `checkAvail` 端点即使对真实 ratePkgId 也返回 param error）
- 这是正常的，**不是 bug**，证明 toolchain 跟 API 通了

**生产环境**：
- 真假 ratePkgId 都能区分：`code: 100000400` 是参数错（包括 fake），`code: 0 + status: 1` 是真可订

**建议**：
- 演示环境用 `/hotel-check-availability --test` 跑 fixture 验证 toolchain
- 真实下单演示环境不可行——请用生产 endpoint + 真实库存
```

#### 分支 D：ARI 变更（`code: 100001111`）—— 真实生产环境的常见情况

**演示环境无法验证**（演示 checkAvail 不返回 ARI changed）。预期响应：

```json
{"code": 100001111, "msg": "ARI changed"}
```
**注意**：ARI 变更的 HTTP 状态是 **200**（不是 409！），但 `.code` 是 100001111。

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

#### 分支 E：API 异常 / 限流

`curl` exit 非 0，或 HTTP 非 2xx，或 `.code` 是其他业务码（如 `100000429` 限流 / `100000500` 系统错）：

```markdown
# API 请求失败

curl exit code / HTTP status：<code>
响应（`.code` + `.msg`）：<前 500 字>

**建议**：
- 等 30 秒重试（429 限流）
- 验证 `ratePkgId` 是否正确（404 找不到）
- 500 系统错：等 1 分钟再试
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
- sessionId 由 hotelbyte server 从 ticket 派生，agent 无需手动维护。

## 兜底分支汇总

| 探测 | 处理 |
|---|---|
| `.code == 0` 且 `.data.status == 1` | 走 A 分支（可订）—— **真实生产环境** |
| `.code == 0` 且 `.data.status == 2` | 走 B 分支（不可订）—— **真实生产环境** |
| `.code == 100000400` + msg `param error` | 走 C 分支（参数错 / 演示环境**必然**） |
| `.code == 100001111` + msg `ARI changed` | 走 D 分支（ARI 变更）—— **真实生产环境** |
| `.code == 100000404` / `.code == 100000429` / 其他非 0 | 走 E 分支（API 异常） |
| `curl` exit 非 0 / HTTP 非 2xx | 走 E 分支（HTTP 4xx/5xx） |
| `ratePkgId` 含空格 / 看起来不对 | 反问："ratePkgId 应是从 /hotel-search 复制的长字符串" |

## `--test` 模式

如果 `$ARGUMENTS` 含 `--test`，跑固定 fixture：

```
ratePkgId=10000000<HB>-1<HB>E2-NRF|20260924|20260926（演示环境 /hotel-search 返回的真实 ratePkgId）
```

**演示环境下**：预期返回**分支 C（code: 100000400, msg: param error）**——这是正常的，演示环境的 `checkAvail` 端点限制。

输出顶部加 `[fixture] check availability`。用于 toolchain 验证。

## 不要做的事

- 不要跳过本 skill 直接 `/hotel-book`——hotelbyte 文档明确要求 verify-before-commit
- 不要把 snapshot 价格当成"永恒价格"——> 60 秒就要重新 verify
- 不要把演示凭据写进任何文件 / 文档 / commit
- 不要用 `Bash(*)` 宽权限——本命令只能调 `curl` + `jq`
- 不要瞎编 `ratePkgId` —— 真实 ID 只能从 `/hotel-search` 响应拿