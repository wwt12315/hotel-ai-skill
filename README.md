# hotel-ai-skill

> **Agent-tool-agnostic** skill pack for booking hotel rooms through the
> [hotelbyte](https://openapi.hotelbyte.com) OpenAPI. Single source-of-truth
> works for **Claude Code, Cursor, Codex, GitHub Copilot, Cline** — any agent
> that can load Markdown + YAML.

> ⚠️ **演示环境实测发现**：hotelbyte 测试环境 (`api-test.hotelbyte.com`) 的
> `hotelStaticDetail` 接口**不**返回房型与 `ratePkgId`，因此本 skill pack
> 不含 `/hotel-detail` 命令；价格 / 库存的最终确认必须经由 `hotel-check-availability`。

---

## 这是什么

一套让 AI agent **直接帮客户预订酒店**（不只是推荐）的 skill 协议：

| 能力 | 作用 |
|---|---|
| `hotel-search` | 自然语言 → 调用 `/api/search/hotelList` → 返回酒店列表 + 解读 |
| `hotel-check-availability` | 验证某个 `ratePkgId` 当前是否可订（hotelbyte 文档要求 "verify before commit"） |
| `hotel-book` | Dry-run 默认；`--confirm` 才真下单并轮询订单状态（`/api/trade/book` + `/api/trade/queryOrders`） |
| `hotel-cancel` | Dry-run 默认；`--confirm` 才真取消并轮询（`/api/trade/cancel` + `/api/trade/queryOrders`） |

**完整预订闭环**：

```
hotel-search ──→ hotel-check-availability ──→ hotel-book [--confirm] ──→ hotel-cancel [--confirm]
  (只读)             (只读)                    (写入)                       (写入)
```

---

## 与 `.claude/commands/` 的差别（迁移记录）

旧版本使用 `.claude/commands/<name>.md`，是 **Claude Code 工具私有的**命令机制：
- 触发依赖 `/` 前缀，别的 agent 工具（Cursor / Codex / Copilot / Cline）识别不到
- frontmatter 字段（`allowed-tools`, `argument-hint`）是 Claude Code 私有扩展
- 没有机器可读的 manifest，要靠 agent 工具自己扫目录 + parse frontmatter

**新版改用 hotelbyte 标准 agent 工具无关 skills 协议**（对齐
`.shared/skills/<skill-name>/SKILL.md` + `MANIFEST.yaml` 双层结构）：

```
hotel-ai-skill/
├── MANIFEST.yaml                 # agent 无关的机器可读索引（schema: hotelbyte-skill-pack/v1）
├── skills/
│   ├── hotel-search/SKILL.md     # 标准 frontmatter（只含 name + description）
│   ├── hotel-check-availability/SKILL.md
│   ├── hotel-book/SKILL.md
│   └── hotel-cancel/SKILL.md
└── README.md
```

**frontmatter 只声明两件事**：
- `name` — skill 的稳定 ID
- `description` — 含触发词的描述，agent 据此判断是否触发；遵循
  hotelbyte `writing-great-skills` 的"leading word + 多 trigger phrase"原则

**agent-specific 字段（`allowed-tools` / `argument-hint`）放进 SKILL.md 正文
「工具权限建议」段**。需要时由各 agent 的 discovery adapter 自行映射，
本仓库不绑定任何特定 agent。

---

## Agent 接入方式

任何能消费 Markdown + YAML 的 agent 都可以用这个仓库。三种方式：

### 方式 1：直接读 MANIFEST.yaml（推荐）

```python
import yaml
with open('MANIFEST.yaml') as f:
    pack = yaml.safe_load(f)
for skill in pack['skills']:
    print(skill['name'], '→', skill['description'][:60])
    print('  triggers:', skill['triggers'])
    print('  dry_run_by_default:', skill['dry_run_by_default'])
```

输出的 4 个 skill 即为可消费索引。`inputs` / `outputs` 段是 typed
JSON Schema 风格描述（简化版，足够给 LLM 解析），符合 hotelbyte
`agent-dev-contract` Pattern 2（typed I/O）契约。

### 方式 2：Claude Code / Cursor 落盘到对应 skills 目录

```bash
# Claude Code（注意是 .claude/skills 不是 .claude/commands）
mkdir -p .claude/skills
for s in hotel-search hotel-check-availability hotel-book hotel-cancel; do
  ln -s ../../skills/$s .claude/skills/$s
done
```

```bash
# Cursor
mkdir -p .cursor/skills
for s in hotel-search hotel-check-availability hotel-book hotel-cancel; do
  ln -s ../../skills/$s .cursor/skills/$s
done
```

### 方式 3：把本仓库整体作为 git submodule

```bash
git submodule add https://github.com/wwt12315/hotel-ai-skill.git .shared/third-party-skills/hotel-ai-skill
# 然后在 .shared/skills/ 下做 symlink，或直接交给 agent 的 discovery 层
```

---

## 安全契约（hotelbyte `agent-dev-contract` 对齐）

| 模式 | 落地 |
|---|---|
| Pattern 5 Tool Use | 每个 skill 在 MANIFEST 声明 typed inputs / outputs；不允许自由文本透传 |
| Pattern 13 Human-in-the-Loop | `hotel-book` / `hotel-cancel` 默认 Dry-run，必须显式 `--confirm` 才执行；agent **不得**自动加 `--confirm` 即使用户说"继续" |
| 7 条诚实契约 | 不伪造酒店列表；4xx/5xx 返回结构化 gap；demo 凭据不进任何持久化文件；ticket 仅内存持有 |

### Dry-run 默认行为

- `hotel-search` / `hotel-check-availability`：纯读，不需 `--confirm`
- `hotel-book` 默认输出"准备下单"清单（ratePkgId / guest / total price），**不**调用 `/api/trade/book`
- `hotel-cancel` 默认先调 `/api/trade/queryOrders` 查状态，输出"准备取消"清单，**不**调用 `/api/trade/cancel`
- 加上 `--confirm` 才执行写入操作，并自动轮询直到终态或 18×10s 超时

### Idempotency

`customerReferenceNo` 作为幂等键：重试同一请求不会重复下单。生成方法见
`uuidgen` 命令，每次新请求换一个值（除非显式 retry）。

---

## 演示环境实测限制（重要）

| 现象 | 原因 | 影响 |
|---|---|---|
| `hotelStaticDetail` 只返回酒店静态信息 | 演示供应商未配置静态详情档 | 不影响 `/hotel-search`；如需房型价格必须走 `hotel-check-availability` |
| `hotel-search` 经常返回 `status=failed / reason=no_availability` | 演示供应商对远期日期无可用库存 | 建议目的地选 Hong Kong / Bangkok / Singapore；或日期往后挪 30-90 天 |
| `hotel-check-availability` 报 `session not found` | Session-Id 与 `/api/auth/ticket` 不在同一进程 | 必须用同一 ticket 在同一 session 内查；ticket TTL 默认 3600s |
| `hotel-book` 报 `ratePkgId validation failed` | 演示环境不返回真实可订的 ratePkgId | **端到端下单无法在演示环境验证**；生产 partner key 才能跑通 |
| 4xx branch（400 / 401 / 404 / 500） | hotelbyte 通用错误码 | 4 个 SKILL.md 都已实测覆盖 |

> **已实现 ≠ 已端到端验证**：`hotel-book` / `hotel-cancel` 的"非 happy path"分支
> 通过 curl 实测验证；"happy path"在演示环境无法走通，需真实 partner key。
> 这是 hotelbyte 演示环境的客观限制，不是 skill 的问题。

---

## 文件清单

```
hotel-ai-skill/
├── MANIFEST.yaml                          # 214 行，agent 无关的机器可读索引
├── README.md
└── skills/
    ├── hotel-search/SKILL.md              # 自然语言 → 酒店列表
    ├── hotel-check-availability/SKILL.md  # 验价 + 验库存（verify before commit）
    ├── hotel-book/SKILL.md                # 下单（Dry-run 默认，--confirm 执行）
    └── hotel-cancel/SKILL.md              # 取消（Dry-run 默认，--confirm 执行）
```

---

## 协议参考

- hotelbyte 内部标准：`.shared/skills/<skill-name>/SKILL.md` + `MANIFEST` + 三层 discovery（详见 `DISCOVERY.md`）
- 协议字段：YAML frontmatter 仅含 `name` / `description` / 可选 `disable-model-invocation`；agent 私字段（`allowed-tools`、`argument-hint`）下沉到正文
- 诚实契约：hotelbyte `.shared/skills/agent-dev-contract`（21 模式 + 7 条不可协商契约 + 15 条欺骗红线）
- 元 skill：hotelbyte `.shared/skills/writing-great-skills`（frontmatter 写法、信息层级、leading word）

---

## 演示凭据

- Base URL：`https://api-test.hotelbyte.com`
- AppKey：`hotelbyte_api_demo`
- AppSecret：`hotelbyte_api_demo`

演示环境公网可调，免注册。**仅**演示环境使用；生产请向 hotelbyte 申请 partner key。
