# hotel-search-skill

一个让 AI 直接帮客户搜索酒店（甚至预订）的 Claude Code slash command MVP，对接 [hotelbyte](https://github.com/hotelbyte-com) 公开测试 API。

> 起源：参考 zread.ai / TourMind 之类的"AI 直接订酒店"产品形态，做一个最小可运行版本。

## 这个仓库里有什么

```
hotel-search-skill/
├── .claude/
│   └── commands/
│       ├── hotel-search.md        # 核心：/hotel-search slash command
│       └── hello.md               # smoke test：验证 Claude Code 项目级 command 工作正常
└── docs/
    └── skill-outputs/
        ├── hotel-search.md        # 使用说明 + 已知限制
        └── run-fixture.ps1        # PowerShell 5.1 fixture 脚本（手把手跑一遍 happy path）
```

## 一句话能干什么

在 Claude Code 里输入：

```
/hotel-search 我下周五去东京，2 晚，2 个大人，预算每晚 200 美元以内，要 4 星以上
```

Claude 会：

1. 解析自然语言 → 拿到 `destination / checkIn / checkOut / adultCount / currency / price / starRating`
2. 用 hotelbyte 公开测试凭据换 ticket（`POST /api/auth/ticket`）
3. 调酒店列表搜索（`POST /api/search/hotelList`），按 hotelId 去重 + minPrice 升序挑前 5–8 家
4. 输出 Markdown 表格 + 自然语言解读 + 推荐结论

## 当前阶段的能力边界（明确告诉你能/不能做什么）

| 能做 | 不能做 |
|---|---|
| 搜索酒店（按城市、日期、人数、价格、星级） | 直接下单（`/hotel-book` 是下一阶段） |
| 解析自然语言查询（中文/英文、相对日期） | 真实下单后改单/取消（`queryOrders` / `cancel`） |
| 把 API 返回结构化成易读解读 | 行程规划、机票、打包清单（另立项） |
| 在任意 Claude Code 项目里通过 `.claude/commands/` 项目级生效 | 不在 Claude Code 之外的 CLI（如裸 bash）直接生效 |

下一阶段会加 `/hotel-detail` 看房型详情、`/hotel-book` 下单 + 轮询订单状态。

## 安全约束（设计时就内嵌了）

- **narrow permissions**：slash command 只允许 `Bash(curl:*)` / `Bash(date:*)` / `Bash(uuidgen:*)`，绝不开放 `Bash(*)` 全权限
- **不持久化 ticket**：ticket 只活在当次 session，不写 `.claude/memory.db`、不进 commit
- **公开凭据**：用的是 hotelbyte 公开测试凭据（`api-test.hotelbyte.com` 免注册），不涉及真实账号密钥
- **不改后端**：本仓库纯新增文件，不修改 `hotel-be` / `hotel-fe` / `sdk-go` 等任何 submodule

## 怎么本地验证

### 方法一：在 Claude Code 里跑

```bash
# 在项目根目录
claude

> /hello                                      # smoke test
> /hotel-search Tokyo 20260828 20260830 2 200 4   # happy path
> /hotel-search 北京 下周五 2晚 2人               # 中文 + 相对日期
```

### 方法二：用 PowerShell fixture 脚本

```powershell
# 不需要 Claude Code，直接看 API 行为
.\docs\skill-outputs\run-fixture.ps1
```

预期输出：拿到 `ticket`，然后 `no_availability`（测试 API 无真实库存，符合预期）。

## 环境

- Windows 10/11 + PowerShell 5.1
- Claude Code CLI（任意 LLM 后端，因为 skill 只描述流程）
- `curl`（Windows 自带即可，支持 Schannel TLS）

## 已知限制

1. **TLS 证书**：hotelbyte 测试 API 证书可能过期，脚本用 `curl -k`（Schannel 兼容）跳过校验。如要严格校验证书，需要 hotelbyte 续期。
2. **测试 API 无真实库存**：`POST /api/search/hotelList` 在测试环境**始终**返回 `no_availability` 分支。这不是 bug，是预期——证明整个 happy path + 兜底分支都通。
3. **自然语言日期**：相对日期（"下周五"、"明天"）解析由 LLM 完成，复杂度受模型能力限制。模糊时建议用绝对日期（`YYYYMMDD`）。

## 参考

- hotelbyte 公开测试 API 文档：`https://api-test.hotelbyte.com`
- 设计参考：zread.ai、TourMind（AI 直接订酒店的产品形态）

## License

私有仓库，仅供内部演示。