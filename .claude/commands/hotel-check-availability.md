---
name: hotel-check-availability
description: 在 /hotel-detail 之后、/hotel-book 之前调用。验证某个 ratePkgId 当前是否可订、价格是否变化、库存是否仍在。文档明确要求"verify before commit"，跳过此步直接下单可能因 ARI 变更被拒。
allowed-tools: Bash(curl:*), Bash(date:*), Bash(uuidgen:*)
---

# /hotel-check-availability

在 `/hotel-detail` 拿到 `ratePkgId` 之后、下单之前跑一次。hotelbyte 文档明确要求"verify before commit"——价格和库存可能在你查询后的几秒内变动，跳过此步直接下单可能被拒。

## API 配置

- 端点：`/api/search/checkAvail`
- Base URL：`https://api-test.hotelbyte.com`
- AppKey：`hotelbyte_api_demo`
- AppSecret：`hotelbyte_api_demo`
- 业务 Header 集合：
  - `Authorization: Bearer <ticket>`（ticket 从 `/api/auth/ticket` 拿，**含 `ST:` 前缀原样使用**）
  - `Session-Id: <uuid4>`（**预订流程必填**——本端点也强制要求）
  - `Language: <IETF BCP 47>`（默认 `en-US`）
  - `Currency: <ISO 4217>`（默认 `USD`）
  - `Content-Type: application/json`

> **本机环境提示**：ZCode 自带 WebFetch 工具证书过期，无法直连 hotelbyte。本命令用 `curl`（Windows Schannel TLS 兼容），`allowed-tools` 已限定 `Bash(curl:*)`。

## 用户输入

```
$ARGUMENTS
```

支持的形态：
- `/hotel-check-availability <ratePkgId>` —— 基础用法
- `/hotel-check-availability <ratePkgId> ja-JP USD` —— 指定语言 + 币种
- `/hotel-check-availability --test` —— 用固定 fixture 回归

## 字段说明

| 字段 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `ratePkgId` | 是 | — | 必须从 `/hotel-detail` 结果里拿，**不能瞎编** |
| `language` | 否 | `en-US`（中文输入 → `zh-CN`） | IETF BCP 47 |
| `currency` | 否 | `USD` | ISO 4217 |

**`ratePkgId` 缺失或模糊**：反问一次。它看起来像长字符串（如 `RP461850557-1234567890`），告诉用户从 `/hotel-detail` 输出表格的"报价 ID"列复制。

## 流程

### 步骤 1：换 ticket（跟 `/hotel-search` `/hotel-detail` 完全一致）

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

### 步骤 2：检查可用

```bash
curl -sS -k -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ST:0Va7n..." \
  -H "Session-Id: $(uuidgen)" \
  -H "Language: en-US" \
  -H "Currency: USD" \
  -d '{"ratePkgId":"RP461850557-1234567890"}' \
  https://api-test.hotelbyte.com/api/search/checkAvail
```

### 步骤 3：解读响应（3 个分支）

**关键字段位置**（文档 §CheckAvail）：

#### 分支 A：可订（`status: 1`）—— 最佳情况

```json
{
  "code": 0,
  "msg": "",
  "data": {
    "status": 1,
    "roomRatePkg": {
      "ratePkgId": "RP461850557-1234567890",
      "refundableMode": "full",
      "refundableUntil": "2026-08-25T23:59:59Z",
      "rate": {
        "netRate": {"currency": "USD", "amount": 185.00},
        "commissionableRate": {"currency": "USD", "amount": 195.00},
        "grossRate": {"currency": "USD", "amount": 200.00},
        "respectGrossRate": false
      },
      "totalRate": {
        "netRate": {"currency": "USD", "amount": 555.00},
        "commissionableRate": {"currency": "USD", "amount": 585.00},
        "grossRate": {"currency": "USD", "amount": 600.00}
      },
      "checkIn": "2026-08-28",
      "checkOut": "2026-08-30",
      "board": {"boardId": "BB", "boardName": "Bed & Breakfast"},
      "tax": {"total": {"currency": "USD", "amount": 30.00}},
      "cancelFees": [
        {"until": "2026-08-25T23:59:59Z", "fee": {"currency": "USD", "amount": 0.00}}
      ]
    },
    "exchangeRateSnapshot": {
      "date": "2026-08-21",
      "usd": {"USD": 1.0, "EUR": 0.92}
    }
  }
}
```

输出：

```markdown
# ✅ 可订：<ratePkgId>

**价格**（snapshot 时点 <asOf>）：
- 单价：<netRate> / <commissionableRate> / <grossRate>
- 总价：<totalRate>（多间多晚）
- 汇率快照：<exchangeRateSnapshot>

**取消政策**：
- 模式：<refundableMode: full/partial/no 翻译>
- 截止：<refundableUntil>
- 阶梯：<cancelFees 列表>

**餐食**：<board.boardId>（<boardName>）

**下一步**：✅ 确认无误，请用 `/hotel-book <ratePkgId> <FirstName> <LastName> <email> [--confirm]`

> 提示：snapshot 价格只在当前会话有效。如果你隔了 1 分钟才下单，**请重新跑一次** `/hotel-check-availability`。
> session=<sessionId>
```

#### 分支 B：不可订（`status: 2`）

```json
{
  "code": 0,
  "msg": "",
  "data": {
    "status": 2
  }
}
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
- 重新跑 `/hotel-detail` 拿新的 ratePkgId
- 选另一个房型或酒店
- 用 `/hotel-search` 重新搜索
```

#### 分支 C：ARI 变更（`code: 100001111`）

```json
{
  "code": 100001111,
  "msg": "ARI changed"
}
```

输出：

```markdown
# ⚠️ 价格/库存已变更：<ratePkgId>

API 返回 `code: 100001111`, `msg: "ARI changed"`。

**含义**：Availability / Rates / Inventory 三个维度中至少一个变了。最常见是：
- 价格小幅上涨（供应商定价刷新）
- 库存被其他人订了
- 房型被下架

**建议**：
- **强制重新跑** `/hotel-detail` 拿最新 ratePkgId 和价格
- 显示新价格给用户对比：
  - 旧总价：<旧值>
  - 新总价：<新值>
- 如果用户接受新价格 → 用新 ratePkgId 再跑 `/hotel-check-availability`
- 如果用户不接受 → 选别的房型
```

#### 分支 D：参数错误（`code: 100000400`）

```json
{"code":100000400,"msg":"ratePkgId is required"}
```

直接报告 `code` 和 `msg`，让用户检查输入。

#### 分支 E：API 异常 / 限流

```markdown
# API 请求失败

HTTP 状态码：<code>
响应：<前 500 字>

**建议**：
- 等 30 秒重试（429 限流）
- 验证 `ratePkgId` 是否正确（404 找不到）
```

## 跟其他 skill 的衔接

**`/hotel-detail` → `/hotel-check-availability` → `/hotel-book`**

```
/hotel-detail 461850557
   ↓ 输出 ratePkgId（如 RP461850557-1234567890）
/hotel-check-availability RP461850557-1234567890
   ↓ 分支 A：可订 → 给出 snapshot 价格
/book RP461850557-1234567890 张三 zhangsan@example.com --confirm
   ↓ 下单 + 轮询订单
```

**关键约束**：
- 从 `/hotel-check-availability` 拿到 snapshot 到 `/hotel-book` 调用，**应 < 60 秒**。超过 1 分钟重新 verify。
- `/hotel-check-availability` 跟 `/hotel-book` 必须**使用同一个 Session-Id**，否则 hotelbyte 会判为不同会话拒绝。我建议 `/hotel-book` 内部复用上一个 `/hotel-check-availability` 的 Session-Id。

## 兜底分支汇总

| 现象 | 处理 |
|------|------|
| `data.status == 1` | 走 A 分支（可订） |
| `data.status == 2` | 走 B 分支（不可订） |
| `code == 100001111` | 走 C 分支（ARI 变更） |
| `code == 100000400` | 走 D 分支（参数错） |
| 其他 `code != 0` | 走 E 分支（API 异常） |
| `curl` 退出码非 0 | 重跑一次 + 报告 stderr |
| `data.ticket` 缺失 | 检查 `msg`，可能是 appKey 失效 |
| `ratePkgId` 含空格 / 看起来不对 | 反问："ratePkgId 应是从 /hotel-detail 复制的长字符串" |

## `--test` 模式

如果 `$ARGUMENTS` 含 `--test`，忽略其余输入，跑固定 fixture：

```
ratePkgId=RP461850557-1234567890（文档示例 ID，演示环境大概率返回 ARI changed 或 status 2）
language=en-US
currency=USD
```

输出顶部加 `[fixture] check availability`。用于 toolchain 验证。**预期结果**：演示环境大概率返回 B 或 C 分支——这是正常的，证明 check-before-commit 流程在跑。

## 不要做的事

- 不要跳过本 skill 直接 `/hotel-book`——hotelbyte 文档明确要求 verify-before-commit
- 不要把 snapshot 价格当成"永恒价格"——> 60 秒就要重新 verify
- 不要把演示凭据 `hotelbyte_api_demo` 写进任何文件 / 文档 / commit
- 不要用 `Bash(*)` 宽权限——本命令只能调 `curl` / `date` / `uuidgen`
- 不要把 ticket 持久化到 `.claude/memory.db`
- 不要瞎编 `ratePkgId` —— 真实 ID 只能从 `/hotel-detail` 来
