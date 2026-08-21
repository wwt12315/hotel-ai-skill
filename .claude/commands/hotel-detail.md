---
name: hotel-detail
description: 看酒店详情（房型 + 价格 + 取消政策）。调用 hotelbyte 公开测试 API 的 /api/search/hotelStaticDetail，返回结构化房型表 + 自然语言解读。
allowed-tools: Bash(curl:*), Bash(date:*), Bash(uuidgen:*)
---

# /hotel-detail

拿到一个 `hotelId` 后，查酒店详情：房型列表、每个房型的价格（单价 / 总价）、餐食计划、取消政策。

## API 配置

- 端点：`/api/search/hotelStaticDetail`
- Base URL：`https://api-test.hotelbyte.com`
- AppKey：`hotelbyte_api_demo`
- AppSecret：`hotelbyte_api_demo`
- 业务 Header 集合：
  - `Authorization: Bearer <ticket>`（ticket 从 `/api/auth/ticket` 拿，**含 `ST:` 前缀原样使用**）
  - `Session-Id: <uuid4>`（每次新生成）
  - `Language: <IETF BCP 47>`（中文输入用 `zh-CN`，默认 `en-US`）
  - `Currency: <ISO 4217>`（默认 `USD`）
  - `Content-Type: application/json`

> **本机环境提示**：ZCode 自带 WebFetch 工具证书过期，无法直连 hotelbyte。本命令用 `curl`（Windows Schannel TLS 兼容），`allowed-tools` 已限定 `Bash(curl:*)`。

## 用户输入

```
$ARGUMENTS
```

支持的形态：
- `/hotel-detail 461850557` —— 一个 hotelId
- `/hotel-detail 461850557 ja-JP` —— 指定语言
- `/hotel-detail 461850557 USD en-US` —— 指定币种 + 语言
- `/hotel-detail --test` —— 用固定 hotelId 跑回归

## 字段说明

| 字段 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `hotelId` | 是 | — | 必须从 `/hotel-search` 结果里拿，不能瞎编（演示环境不接受随机 ID） |
| `language` | 否 | `en-US`（中文输入 → `zh-CN`） | IETF BCP 47 |
| `currency` | 否 | `USD` | ISO 4217 |

**`hotelId` 缺失或模糊**：反问一次。如果用户给的 hotelId 看起来不是数字（hotelbyte 的 ID 是数字字符串），提示一句"hotelId 应该是从搜索结果里拿的纯数字 ID"。

## 流程

### 步骤 1：换 ticket（跟 `/hotel-search` 完全一致的流程）

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

### 步骤 2：查酒店详情

```bash
curl -sS -k -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ST:0Va7n..." \
  -H "Session-Id: $(uuidgen)" \
  -H "Language: en-US" \
  -H "Currency: USD" \
  -d '{"hotelId":"461850557"}' \
  https://api-test.hotelbyte.com/api/search/hotelStaticDetail
```

### 步骤 3：解读响应（5 个分支）

响应外层结构：`{"code":0,"msg":"","data":{"hotel":{...}}}` 或 `{"code":100000xxx,"msg":"..."}`

**关键字段位置**（文档 §HotelStaticDetail）：
- `data.hotel.id` —— 酒店 ID
- `data.hotel.name.en / .zh / .ar` —— 多语言名
- `data.hotel.rating` —— 评分 [0.0, 5.0]
- `data.hotel.address.en / .zh / .ar` —— 多语言地址
- `data.hotel.logoURL` —— logo
- `data.hotel.latlngCoordinator.google` —— `{lat, lng}`
- `data.hotel.rooms[]` —— 房型列表
- `data.hotel.rooms[].roomTypeId`
- `data.hotel.rooms[].roomTypeName.en / .zh`
- `data.hotel.rooms[].rates[]` —— 房型下的报价包列表
- `data.hotel.rooms[].rates[].ratePkgId` —— **下一步 `/hotel-check-availability` 用这个**
- `data.hotel.rooms[].rates[].rate.netRate` / `commissionableRate` / `grossRate` —— 单房价
- `data.hotel.rooms[].rates[].totalRate` —— 总价（多间多晚）
- `data.hotel.rooms[].rates[].refundableMode` —— `full` / `partial` / `no`
- `data.hotel.rooms[].rates[].refundableUntil` —— RFC3339
- `data.hotel.rooms[].rates[].cancelFees[]` —— `[{until, fee:{currency, amount}}]`
- `data.hotel.rooms[].rates[].board.boardId` —— `RO` / `BB` / `HB` / `FB` / `AI` 等
- `data.hotel.rooms[].rates[].checkIn` / `checkOut` —— DateInt `YYYY-MM-DD` 格式

#### 分支 A：正常返回（含 hotel + rooms）

输出：

```markdown
# 酒店详情：<name>（<id>）

**评分**：<rating>/5
**地址**：<address>
**坐标**：<lat>, <lng>
**Logo**：<logoURL>

## 房型与报价

| # | 房型 | 报价 ID | 餐食 | 单价 | 总价 | 取消政策 |
|---|------|---------|------|------|------|----------|
| 1 | <roomTypeName> (Deluxe) | <ratePkgId> | BB | 185.00 USD | 555.00 USD | 免费取消至 <refundableUntil> |
| 2 | <roomTypeName> (Standard) | <ratePkgId> | RO | 150.00 USD | 450.00 USD | 不可退 |
| ... |

## 推荐
<1-2 段：基于房型、报价、取消政策给推荐>

> **下一步**：挑一个 `ratePkgId`，用 `/hotel-check-availability <ratePkgId>` 确认当前可订，再用 `/hotel-book` 下单。
> session=<sessionId>
```

**餐食 board 翻译表**（用于人类可读）：
- `RO` = 仅房 (Room Only)
- `BB` = 含早 (Bed & Breakfast)
- `HB` = 半食宿 (Half Board)
- `FB` = 全食宿 (Full Board)
- `AI` = 全包 (All Inclusive)

**取消政策翻译表**：
- `full` = 全部可退（在 `refundableUntil` 之前）
- `partial` = 部分退（按 `cancelFees` 阶梯收费）
- `no` = 不可退

#### 分支 B：酒店 ID 找不到

```markdown
# 酒店 <hotelId> 不存在

API 返回 `code: 100000xxx`，msg: "..."。

**可能原因**：
- hotelId 输错（演示环境的 hotelId 必须从 `/hotel-search` 结果里拿）
- 演示环境的库存已经清空（这是常见情况）

**建议**：
- 用 `/hotel-search` 重新找一家
- 用 `/hotel-detail --test` 跑 fixture 看 toolchain 是否工作
```

#### 分支 C：参数错误（如 hotelId 为空）

```markdown
# 参数错误

API 返回 `code: 100000400`, `msg: "hotelId is required"`。

请提供一个 hotelId，从 `/hotel-search` 结果里拿。
```

#### 分支 D：API 异常 / 限流

```markdown
# API 请求失败

HTTP 状态码：<code>
响应：<前 500 字>

**建议**：
- 等 30 秒重试（429 限流）
- 换用 `/hotel-detail --test` 验证 toolchain
```

#### 分支 E：rooms 列表为空

```markdown
# 酒店 <hotelId> 暂无房型

酒店信息已返回，但 `rooms` 数组为空。

**可能原因**：
- 演示供应商在该酒店暂时没有库存
- 这是该酒店的"壳信息"，需要等待正式库存

**建议**：
- 换一家（用 `/hotel-search`）
- 等真实库存上线
```

### 步骤 4：下一个 skill 的衔接

**重要**：把 `ratePkgId` 记下来，下一步给 `/hotel-check-availability` 或 `/hotel-book` 用。

- 如果用户说"下一步"或"下单" → 提示："请用 `/hotel-book <ratePkgId> <姓名> <email> [--confirm]`"
- 如果用户说"换个房型" → 列当前所有房型让用户选
- 如果用户单纯想知道详情 → 步骤 3 分支 A 输出即可

## 兜底分支汇总

| 现象 | 处理 |
|------|------|
| `data.hotel` 缺失 | 走 B 分支（hotelId 不存在） |
| `data.hotel.rooms` 空数组 | 走 E 分支（无房型） |
| `code != 0` | 走 B/C 分支（hotelId 错或参数错） |
| `curl` 退出码非 0 | 重跑一次 + 报告 stderr |
| `data.ticket` 缺失 | 检查 `msg`，可能是 appKey 失效 |
| `hotelId` 含非数字 | 反问："hotelId 应该是数字 ID，从搜索结果里拿的" |

## `--test` 模式

如果 `$ARGUMENTS` 含 `--test`，忽略其余输入，跑固定 fixture：

```
hotelId=461850557（hotelbyte 官方文档示例 ID）
language=en-US
currency=USD
```

输出顶部加 `[fixture] hotel static detail`。用于 toolchain 验证。

## 不要做的事

- 不要调 `/api/trade/book`（本 skill 只读详情，不做预订）
- 不要把演示凭据 `hotelbyte_api_demo` 写进任何文件 / 文档 / commit
- 不要用 `Bash(*)` 宽权限——本命令只能调 `curl` / `date` / `uuidgen`
- 不要把 ticket 持久化到 `.claude/memory.db`（凭据类不进 memory）
- 不要瞎编 `hotelId` —— 演示环境的真实 hotelId 只能从 `/hotel-search` 结果里来
