# hotel-ai-skill

让 AI 直接帮客户**搜索、预订、取消酒店**的 Claude Code slash command 集合，对接 [hotelbyte](https://github.com/hotelbyte-com) 公开测试 API。

> 起源：参考 zread.ai / TourMind 之类的"AI 直接订酒店"产品形态，做一个最小可运行版本，覆盖**搜索 → 验证 → 下单 → 取消**完整闭环。

## 这个仓库里有什么

```
hotel-ai-skill/
├── README.md                          # 你正在看的这份文档
├── .claude/
│   └── commands/
│       ├── hello.md                       # /hello —— smoke test
│       ├── hotel-search.md                # /hotel-search —— 自然语言搜索
│       ├── hotel-check-availability.md    # /hotel-check-availability —— 下单前预检
│       ├── hotel-book.md                  # /hotel-book —— 下单（默认 Dry-run）
│       └── hotel-cancel.md                # /hotel-cancel —— 取消订单（默认 Dry-run）
└── docs/
    └── skill-outputs/
        ├── hotel-search.md                # /hotel-search 详细使用文档
        └── run-fixture.ps1                # PowerShell 5.1 fixture 脚本
```

## 4 个 slash command 一览

| 命令 | 触发时机 | 端点 | 关键输出 |
|---|---|---|---|
| `/hello` | 验证 Claude Code 项目级 command 能识别 | — | smoke test |
| `/hotel-search <自然语言>` | 起点 | `POST /api/auth/ticket` + `POST /api/search/hotelList` | hotelId + `ratePkgId`（关键） |
| `/hotel-check-availability <ratePkgId>` | 搜索后、下单前 | `POST /api/search/checkAvail` | 价格 snapshot（status: 1 = 可订） |
| `/hotel-book <ratePkgId> <姓名> <email> [--confirm]` | 验证后 | `POST /api/trade/book` + 轮询 `/api/trade/queryOrders` | 真下单 |
| `/hotel-cancel <customerRef> <supplierRef> [--confirm]` | 任何时候 | `POST /api/trade/cancel` + 轮询 `/api/trade/queryOrders` | 取消订单 |

> ⚠️ **设计决策**：`/hotel-detail` 端点（`/api/search/hotelStaticDetail`）已被实测证明**只返回酒店静态信息**（名 / 地址 / 坐标 / minPrice），**不包含房型 / ratePkgId**。功能完全被 `/hotel-search` 输出覆盖，因此本 skill 集合**不包含** `/hotel-detail`。

## 完整使用流程

```
用户：在 Claude Code 里输入
   /hotel-search 我下周五去东京，2 晚，2 个大人，预算每晚 200 美元以内，要 4 星以上
                                    ↓
                           拿到酒店列表 + 每家酒店的 rooms[].rates[].ratePkgId
                                    ↓
   /hotel-check-availability RP461850557-1234567890
                                    ↓
                           拿到价格 snapshot（status: 1 = 可订）
                                    ↓
   /hotel-book RP461850557-1234567890 张三 zhangsan@example.com
                                    ↓
                           输出"准备下单"清单（Dry-run，不真下单）
                                    ↓
   /hotel-book RP461850557-1234567890 张三 zhangsan@example.com --confirm
                                    ↓
                           调 /api/trade/book + 轮询 /api/trade/queryOrders
                                    ↓
                           拿到 platformReferenceNo / supplierReferenceNo
                                    ↓
   /hotel-cancel <customerRef> <supplierRef> --confirm
                                    ↓
                           取消订单
```

## 当前阶段的能力边界

| 能做 | 不能做 |
|---|---|
| 4 个 slash command 覆盖搜索→预检→下单→取消 | 改订单（改日期 / 改房型）——只能"取消后重订" |
| 自然语言查询（中文 / 英文 / 相对日期） | 部分取消（只取消订单的 1 间房） |
| Dry-run 默认 + `--confirm` 真下单 + 轮询验证 | 真实下单场景（演示环境库存稀缺） |
| 任意 Claude Code 项目里通过 `.claude/commands/` 项目级生效 | 在裸 bash / 其他 CLI（不走 Claude Code）生效 |
| 公开测试凭据（hotelbyte_api_demo） | 真实生产凭据（你自己申请 partner key） |

## 安全约束（设计时就内嵌了）

- **narrow permissions**：每个 slash command 只允许 `Bash(curl:*)` / `Bash(date:*)` / `Bash(uuidgen:*)`，**绝不**开放 `Bash(*)` 全权限
- **narrow permissions（book / cancel）**：`Bash(curl:*)` / `Bash(date:*)` / `Bash(uuidgen:*)` / `Bash(sleep:*)`（用于轮询）
- **Dry-run by default**：`/hotel-book` 和 `/hotel-cancel` 默认干跑，**必须**加 `--confirm` 才真下单 / 真取消
- **不持久化 ticket**：ticket 只活在当次 session，不写 `.claude/memory.db`、不进 commit
- **本地订单快照**：写 `.claude/orders/<uuid>.json`（**不**进 memory.db）
- **公开凭据**：演示用的是 hotelbyte 公开测试凭据（`api-test.hotelbyte.com` 免注册），不涉及真实账号密钥
- **不改后端**：本仓库纯新增文件，不修改 `hotel-be` / `hotel-fe` / `sdk-go` 等任何 submodule

## 怎么本地验证

### 方法一：在 Claude Code 里跑完整流程

```bash
# 在项目根目录
claude

> /hello                                                 # smoke test
> /hotel-search Tokyo 20260828 20260830 2 200 4          # happy path
> /hotel-check-availability RP461850557-1234567890       # 验证
> /hotel-book RP461850557-1234567890 张三 zhangsan@example.com        # Dry-run
> /hotel-book RP461850557-1234567890 张三 zhangsan@example.com --confirm  # 真下单
> /hotel-cancel <customerRef> <supplierRef> --confirm    # 取消
```

### 方法二：用 PowerShell fixture 脚本（不依赖 Claude Code）

```powershell
.\docs\skill-outputs\run-fixture.ps1
```

预期输出：拿到 `ticket`，然后 `no_availability`（测试 API 无真实库存，符合预期）。

## 6 步状态机（OrderStatus 文档 §OrderStatus）

| 值 | 名称 | 含义 | 可取消？ |
|---|---|---|---|
| 0 | Unknown | 未知（不应该出现） | ❌ |
| 1 | Confirming | 等待供应商确认 | ✅（趁还没确认） |
| 2 | Confirmed | 已确认 | ✅（**可能要付取消费**） |
| 3 | Cancelled | 已取消 | ❌（幂等） |
| 4 | Failed | 失败 | ❌（终态） |
| 5 | CancelFailed | 取消失败 | ⚠️（重试） |

## 环境

- Windows 10/11 + PowerShell 5.1
- Claude Code CLI（任意 LLM 后端，因为 skill 只描述流程）
- `curl`（Windows 自带即可，支持 Schannel TLS）

## 已知限制

1. **TLS 证书**：hotelbyte 测试 API 证书可能过期，脚本用 `curl -k`（Schannel 兼容）跳过校验。
2. **测试 API 无真实库存**：`POST /api/search/hotelList` 在测试环境**始终**返回 `no_availability` 分支，**真下单/验证/取消都需要真实 ratePkgId**。演示环境能验证的只是错误分支（404 / 格式校验），真实路径需在生产环境/有库存环境验证。
3. **自然语言日期**：相对日期（"下周五"、"明天"）解析由 LLM 完成，复杂度受模型能力限制。模糊时建议用绝对日期（`YYYYMMDD`）。
4. **中文姓名**：传给酒店前必须**拼音化**（CJK 字符可能被拒）。`/hotel-book` 会反问一次确认。
5. **演示环境轮询**：每 10 秒一次，最多 18 次（3 分钟）。真实 confirm 可能需要 5-15 分钟，演示环境超时正常。

## 设计参考

- hotelbyte 公开测试 API 文档：https://openapi.hotelbyte.com
- hotelbyte 测试 API：`https://api-test.hotelbyte.com`
- 产品形态参考：zread.ai、TourMind（AI 直接订酒店的产品形态）

## License

私有仓库（虽然目前是 public 状态）。代码仅供内部演示。
