# /hotel-search 使用说明

> Claude Code slash command，调 hotelbyte 公开测试 API 搜索酒店。
> 对应文件：`.claude/commands/hotel-search.md`

## 触发

在 Claude Code 会话里输入：

```
/hotel-search <你的需求>
```

示例：
- `/hotel-search Tokyo 20260828 20260830 2 200 4`
- `/hotel-search 北京 下周五 2 晚 2 人 预算 300`
- `/hotel-search 我下个月想去巴黎玩 5 天 2 个人`
- `/hotel-search --test`  ← 标准 fixture，回归用

## 它做什么

1. 解析自然语言到结构化参数（destination / checkIn / checkOut / adults / currency / language / 价格区间 / 星级）
2. 调 `POST /api/auth/ticket` 换 JWT（凭据 `hotelbyte_api_demo`）
3. 调 `POST /api/search/hotelList` 拿酒店列表
4. 解读响应，按价格升序挑 5-8 家，输出 Markdown 表格 + 推荐

## 已知限制

- **演示环境库存稀疏**：测试凭据 `hotelbyte_api_demo` 后端供应商对很多日期返回 `no_availability`。常见结果：返回"无可预订酒店"。这是数据问题，不是 skill bug。
- **过去日期不接受**：API 校验 `checkIn > today`（今天 2026-08-20）。SKILL.md 里默认 `today + 7 days`，一般不会踩。
- **依赖 `curl`**：本机 WebFetch 工具证书过期，slash command 必须用 `curl`。Windows 自带，无需装。
- **依赖 `uuidgen`**：Windows 没有 `uuidgen`（Git Bash 才有）。如果 `Bash(uuidgen:*)` 失败，回退方案：用 PowerShell `[guid]::NewGuid().ToString()` 或让 Claude 用任意 UUID 字符串。
- **首次运行可能问权限**：Claude Code 第一次跑 `/hotel-search` 会问要不要允许 `Bash(curl:*)` / `Bash(date:*)` / `Bash(uuidgen:*)`，批准即可。

## 不做的事（明确范围）

- 不下单（`/api/trade/book` 留给后续 skill）
- 不查订单 / 不取消
- 不做行程规划、机票
- 不做 Web 前端
- 不持久化任何用户数据 / ticket

## 后续路线（未做）

- `/hotel-detail <hotelId>`：调 `/api/search/hotelRates` 看房型详情
- `/hotel-book`：调 `/api/trade/checkAvail` → `book` → `queryOrders` 轮询直到 status=2/3/4
- 把 `curl` 调用封装成 MCP server（如果觉得每次重写命令难维护）
- 多轮对话（"换便宜的"、"换有泳池的"）

## 验证记录

| 日期 | 场景 | 结果 |
|------|------|------|
| 2026-08-20 | 换 ticket | ✅ `ST:0Va7n...` |
| 2026-08-20 | Tokyo 2026-08-28/30, 4星+, USD | ✅ 200, `no_availability`（演示无库存） |
| 2026-08-20 | Singapore 2025-12-01（过去日期） | ✅ 200, `code:100000400` |
| 2026-08-20 | Shanghai 中文 zh-CN | ✅ 200, `no_availability` |
| 2026-08-20 | Mars 2099（无效目的地） | ✅ 200, `no_availability`（供应商空） |
| 2026-08-20 | hotelIds=["HC1"]（无效 ID） | ✅ 200, `code:100000400` |

## 文件清单

| 文件 | 状态 |
|------|------|
| `.claude/commands/hotel-search.md` | 新增 |
| `.claude/commands/hello.md` | 新增（smoke test） |
| `docs/skill-outputs/hotel-search.md` | 本文件 |

## 维护要点

- hotelbyte API 改版需同步更新 SKILL.md 里的 endpoint 路径、header 名、响应 schema
- `.claude/AGENTS.md` 说"Hook and permission edits are executable security changes"——本命令的 `allowed-tools` 是窄白名单（只 curl/date/uuidgen），不要扩成 `Bash(*)`
