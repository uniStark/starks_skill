<div align="center">

# starks

**把一句模糊需求送到可验证交付：任务分档、Claude↔Codex 可选互审、轻装 PM 子代理，以及“没证据不算完”。**

[English](README.md) | 简体中文

[![Release](https://img.shields.io/github/v/release/uniStark/starks_skill)](https://github.com/uniStark/starks_skill/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-skill-orange.svg)](https://docs.anthropic.com/en/docs/claude-code)
[![Codex CLI](https://img.shields.io/badge/Codex%20CLI-skill-black.svg)](https://github.com/openai/codex)

</div>

## 为什么做 starks？

很多 Agent 工作流不是太随意，就是太讲仪式：大任务缺少约束，小改动却被流程拖慢。starks 会自己分档——小事轻装上阵，复杂任务才进入需求拷问、方案门禁、PM 编排、两阶段审查和完成验证。

它最有辨识度的设计在两个地方：方案阶段由**用户**决定要不要让 Claude 与 Codex 互相挑刺；执行阶段由主 PM 单向整理最小上下文，子代理不用反复吞 Session 和整套项目文档。

## 特色功能

- **任务分档**——trivial / 轻量 / 完整三档按风险匹配流程。简单任务不交“流程税”，真正复杂的任务才走全套。
- **跨模型互审（用户可选）**——设计文档或重大变更任务在方案门禁可选：**直接开干 / 跨模型互审 / 修改方案**；其余任务默认不互审、不询问，用户随时可主动提出。pi 上 reviewer 由 `subagent` 派发，模型与思考强度由用户从 pi registry 选择；Claude/Codex 上由另一端 CLI 互审。互审不自动触发，也不会失败后偷偷跳过。
- **持续补位调度**——依赖 DAG 与 Ready 队列一有安全任务就填补空闲槽位；强耦合切片保持串行，不为看起来“多线程”而硬拆。
- **轻装子代理**——主 PM 给每个单层子代理一张 **“派活单 + 随身小抄”**。子代理不重读 Session、通用项目文档和近期提交，完工只交一张有长度边界的 **“收工小票”**。
- **真实进度看板**——主 PM 保持响应，只展示真实状态，不虚构百分比和 ETA；执行中仍可接收 `QUERY`、`ADD`、`CHANGE`、`REPLACE`、`PRIORITY`。
- **两阶段审查**——先核对需求与规格，再检查代码质量；不合格切片有限回炉，不会混进一句模糊的“已完成”。
- **完成门禁**——宣称「完成 / 通过 / 修好」之前，必须有与验收标准对应的当场验证证据。
- **内置专项路径**——bug 从复现和根因证据开始，skill 修改核对真实安装入口，高不确定设计进入完整方案门禁；不依赖额外的工作流 skill 插件。
- **双平台、防套娃**——Claude Code 与 Codex 共用一份 `SKILL.md`；一次性互审 Agent 只给意见就退出，不会反向再次调用 starks。

## 招牌 PM 工作流

```text
用户需求
  └─ 任务分档 → 需求拷问 → 起草方案
                              └─ 用户定夺：开干 / 改方案
                                   （设计文档与重大变更另有互审选项，绝不自动触发）
                                               │
PM：依赖 DAG + Ready 队列                       │ 可选 Claude↔Codex 互审
  ├─ 派活单 + 随身小抄 → 单层子代理 A ─┐        │
  ├─ 派活单 + 随身小抄 → 单层子代理 B ─┼─→ 收工小票 ─┘
  └─ 实时更新看板 + 继续接用户新需求 ──→ 规格审查 → 质量审查 → 完成验证
```

主 PM 是唯一的上下文汇合点。子代理只拿到目标、允许读写的文件、必要直接依赖、约束、验收标准和证据要求，而不是整段对话。它可以查看派活单点名的目标文件、必要直接依赖和强制生效的项目规则；发现信息不足就报告 **“缺料”**，不能自行扩大范围。只有 PM 可以派代理，因此代理树始终只有一层，清楚、可控、不套娃。

每个子代理最后只交一张结构化小票：

```text
【收工小票】
- 收工状态：已交卷 / 缺料 / 等老板拍板 / 翻车
- 动了什么：...
- 验收证据：...
- 留下的雷：...
- 产物位置：...
- 建议下一棒：...
```

这张小票直接进入实时看板和审查队列，不把原始长日志、巨型 diff 或重复的项目上下文重新灌回主 PM。

## 环境要求

- Claude Code、Codex CLI **或** pi（任一即可）
- `bash`
- `python3`（用于隔离 reviewer 进程组并执行硬超时）
- macOS 或 Linux
- 跨模型互审：Claude/Codex 上需要**另一端** CLI 在 `PATH` 中（`claude` / `codex`）；pi 上需要 `subagent` 工具，或以任意外部 CLI 兜底
- 可选：`gh`

## 安装

同一份 skill 也可供 pi 使用。pi 会从 `~/.agents/skills/` 发现 skill，因此默认安装脚本会同时服务 pi 和 Codex。若只想显式加载，可使用 `pi --skill /path/to/starks_skill`，或先安装后在 pi 中执行 `/skill:starks`。

```bash
bash scripts/install.sh
```

会把本仓软链到 `~/.claude/skills/starks` 和 Codex 当前生效的 skill 根目录：设置了 `CODEX_HOME` 时使用 `$CODEX_HOME/skills/starks`，否则使用跨客户端通用位置 `~/.agents/skills/starks`。已有普通文件或指向别处的软链不会被覆盖；任一入口验证失败时安装脚本会返回非零。其它已知 Codex 位置中的旧链接，只有在它指向本仓且所有新入口都验证成功后才会被移除。

## 配置

starks 从环境变量读取以下设置（都可选，有默认值或在缺失时优雅跳过）：

| 环境变量 | 作用 | 默认 |
|---|---|---|
| `STARKS_REVIEW_MODEL_CODEX` | Codex 当 reviewer 时（Claude→Codex）使用的模型 | 未设用 Codex 默认 |
| `STARKS_REVIEW_MODEL_CLAUDE` | Claude 当 reviewer 时（Codex→Claude）使用的模型 | 未设用 Claude 默认 |
| `STARKS_REVIEW_TIMEOUT_SECONDS` | 跨模型互审超时秒数 | `600` |
| `STARKS_REVIEW_MODEL_PI` | pi reviewer 模型（registry 中精确的 `provider/id`） | 未设或为空则互审时询问 |
| `STARKS_REVIEW_THINKING_PI` | pi reviewer 思考强度 | 未设或为空则询问（建议 `high`） |
| `STARKS_AGENT_MODEL_PI` | pi 上 PM 派发子代理的默认模型 | 未设或为空则继承平台默认 |
| `STARKS_AGENT_THINKING_PI` | pi 子代理默认思考强度 | 未设或为空则继承平台默认 |

子代理默认继承平台全局默认模型与思考深度；主 PM 可按任务复杂度、风险与成本自行选择平台支持的覆盖参数，同时遵守用户明确配置与平台规则。pi 上也可保存自己的默认子代理模型与思考强度（经 `/skill:starks subagents` 设置台，或完整档方案门禁的顺带一问，从 registry 选择）；已存默认约束所有派发，PM 只能建议偏离。选择不改写全局设置；不支持或未验证的项必须如实说明。详细规则见 [runtime reference](references/runtime.md)。

前三个变量仅控制外部跨模型互审 wrapper，`STARKS_REVIEW_*_PI` 键仅控制 pi 的互审 reviewer，`STARKS_AGENT_*_PI` 键仅控制 pi 的 PM 派发子代理。reviewer 配置也可写入 `.env`；`scripts/cross-review.sh` 会自动读取，调用进程已导出的值优先。pi 键在用户同意“存为默认”时写入 `.env`；随时可用 `/skill:starks cross-review` 与 `/skill:starks subagents` 设置台管理（其余后缀视为任务描述）。

## 工作原理

starks 先对任务**分档**，再决定走多重：

- **trivial**——一行真实改动、显然 typo、已有明确步骤的低风险动作。直接做，不拷问、不互审。
- **轻量**——单一关注点、需求清晰、涉及少数文件、低不确定性。直接做或一句话确认即可；可跳过跨模型互审与并行子代理，但完成门禁仍然适用。
- **完整**——跨多文件 / 架构级 / 行为大改 / 明显不确定性。走完整流程：

  1. **拷问需求**——读取相关文件与必要的近期 commit，合并独立问题，挖出隐藏假设、边界条件与成功标准。
  2. **起草方案**——收口需求并做轻量任务拆解。
  3. **呈现方案 + 用户定夺**——设计文档或重大变更任务交给用户三选：**A 直接开干 / B 跨模型互审再定 / C 修改方案**；其余任务只选 **A / C**，默认不互审、不主动提议，用户随时可要求互审。仅当选 B 才跑互审，整合修订版后回到本步重新定夺。
  4. **PM 持续调度子代理**——安全的 Ready 工作会在槽位释放后持续补位，无需等待整波完成；PM 用“派活单 + 随身小抄”给最小上下文，子代理不套娃、不自行扩域，只用“收工小票”回传结果。
  5. **两阶段审查**——先查规格合规，再查代码质量；不过回炉，最多 2 次，仍不过交回用户定夺。
  6. **完成门禁**——当场跑出验证证据才能宣称「完成 / 通过」。

执行期间，主 PM 保持响应并在 commentary 展示真实进度看板，也能继续接收 `QUERY`、`ADD`、`CHANGE`、`REPLACE`、`PRIORITY` 类新消息。详细协议见 [PM 编排参考](references/pm-orchestration.md) 和 [运行参考](references/runtime.md)。

跨模型互审统一走包装器，方案全文通过 stdin 传递：

```bash
scripts/cross-review.sh codex /path/to/repo < plan.md   # Claude → Codex
scripts/cross-review.sh claude /path/to/repo < plan.md  # Codex → Claude
```

## pi 使用

starks 每次会话探测 pi 的实际能力。有 `subagent` 工具（pi-subagents）时走完整 PM 编排；互审由一次性 reviewer 子代理完成，模型与思考强度由用户选择，可存为 `.env` 默认。没有该工具时顺序降级：呈现方案、等待确认、一次执行一个切片、完成两阶段审查，再运行最终验证。只有完整档且确实需要持久化进度时，才建议使用 `.starks/plan.md` 和 `.starks/board.md`。

```bash
bash scripts/install.sh
pi
# 然后输入：/skill:starks
```

安装脚本不会修改 pi 的认证、模型、settings 或 extensions。子代理默认继承平台全局模型和思考深度；主 PM 只有在平台支持且确有理由时，才选择本次派发的覆盖参数。

## 跨平台

同一份 skill 契约在两个平台上以各自原生工具落地：

| 动作 | Claude | Codex | pi |
|---|---|---|---|
| 派并行子代理 | `Task` / `Agent` 工具 | `spawn_agent`（可用时） | `subagent`（可用时），否则顺序执行 |
| 交互式提问 | `AskUserQuestion` | `request_user_input`（可用时）/ 直接追问 | `ask_user_question` 或直接追问 |
| 进度跟踪 | `TodoWrite` | `update_plan` | `todo`（可用时），否则 `.starks/board.md` |
| 跨模型互审 | `scripts/cross-review.sh codex …` | `scripts/cross-review.sh claude …` | `subagent` reviewer（wrapper 仅用于外部 CLI） |
| 子代理模型 | 平台全局默认或主代理决策 | 平台全局默认或主代理决策 | 平台全局默认或主代理决策（`provider/id:强度`） |

## 卸载

```bash
bash scripts/uninstall.sh
```

只移除已知的 Claude/Codex 软链（包括旧 Codex 位置），且仅当它们确实指向本源仓时才删；绝不删除或改动源仓文件。预览将做什么而不实际删除：

```bash
DRY_RUN=1 bash scripts/uninstall.sh
```

## 许可证

[MIT](LICENSE)

---

设计细节详见 [`docs/DESIGN.md`](docs/DESIGN.md)。
