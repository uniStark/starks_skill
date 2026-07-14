<div align="center">

# starks

**一个个人「任务启动器」skill，同时适配 Claude Code 与 Codex CLI。**

[English](README.md) | 简体中文

[![Release](https://img.shields.io/github/v/release/uniStark/starks_skill)](https://github.com/uniStark/starks_skill/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-skill-orange.svg)](https://docs.anthropic.com/en/docs/claude-code)
[![Codex CLI](https://img.shields.io/badge/Codex%20CLI-skill-black.svg)](https://github.com/openai/codex)

</div>

## 为什么做 starks？

单个模型存在系统性盲区——独自审查自己的方案，往往看不见自己看不见的东西。但简单任务不该被一套重流程拖累，所以 starks 先**按任务分档**决定走多重：琐碎的直接做，复杂的才上全流程。在关键节点，让**另一个**模型（Claude↔Codex）互审方案，能显著降低出错率。一句话：用最轻的开销解决简单事，用跨模型互审守住复杂事。

## 特性

- **任务分档**——trivial / 轻量 / 完整三档，先判断再决定走多重，不让重流程拖累简单任务。
- **跨模型互审（用户可选）**——关键节点把方案交给另一端模型（Claude↔Codex）补盲区、纠错；由用户拍板是否启用，不自动触发。
- **持续补位调度**——完整任务先建立依赖 DAG 与 Ready 队列，安全的 Ready 工作会立即填满空闲槽位；强耦合工作保持串行，不为追求并发而强拆。
- **真实进度看板**——主 PM 保持响应，在 commentary 展示实时进度，并在执行中继续接收 `QUERY`、`ADD`、`CHANGE`、`REPLACE`、`PRIORITY` 类消息。
- **两阶段审查**——先查规格合规，再查代码质量；不过则回炉。
- **完成门禁**——宣称「完成 / 通过 / 修好」之前，必须有当场跑出的验证证据。
- **受控跨项目记忆**——Claude 与 Codex 可共享 Obsidian 事实，但默认不搜索、不列举、不读写；读取按任务授权并受预算约束，写入须另行枚举和确认。
- **双平台**——Claude Code 与 Codex CLI 共用同一份 skill 契约。
- **防递归守卫**——被另一端模型调起做一次性互审时，自动跳过主流程，不会无限套娃。

## 环境要求

- Claude Code **或** Codex CLI（任一即可，两端都装可获得完整跨模型互审能力）
- `bash`
- `python3`（用于隔离 reviewer 进程组并执行硬超时）
- macOS 或 Linux
- 跨模型互审需要**另一端** CLI 在 `PATH` 中（`claude` / `codex`）
- 可选：Obsidian（用作记忆层）与 `gh`
- 推荐：[superpowers](https://github.com/obra/superpowers) 插件——遇到 bug / 写 skill / 大型设计时 starks 会转交它的 `systematic-debugging` / `writing-skills` / `brainstorming`；未安装不影响主流程，只是这些转交不生效

## 安装

```bash
bash scripts/install.sh
```

会把本仓软链到 `~/.claude/skills/starks` 和 `~/.codex/skills/starks`，两端共用同一份 skill 契约。

## 配置

starks 从环境变量读取以下设置（都可选，有默认值或在缺失时优雅跳过）：

| 环境变量 | 作用 | 默认 |
|---|---|---|
| `STARKS_AGENT_MODEL` | 平台支持显式选模型时，请求子代理使用的模型 | 继承平台配置 |
| `STARKS_REVIEW_MODEL_CODEX` | Codex 当 reviewer 时（Claude→Codex）使用的模型 | 未设用 Codex 默认 |
| `STARKS_REVIEW_MODEL_CLAUDE` | Claude 当 reviewer 时（Codex→Claude）使用的模型 | 未设用 Claude 默认 |
| `STARKS_REVIEW_TIMEOUT_SECONDS` | 跨模型互审超时秒数 | `600` |
| `STARKS_MEMORY_DIR` | 共享项目记忆根目录（如某 Obsidian vault 子目录）；配置后仅提供按任务授权选项 | 未设置 |
| `STARKS_STYLE_NOTE` | 可选：记忆写手在动笔前先读的文风笔记路径 | 未设置 |

子代理和记忆配置需导出到主代理进程。reviewer 配置也可写入 `.env`；`scripts/cross-review.sh` 会自动读取，调用进程已导出的值优先。

## 工作原理

starks 先对任务**分档**，再决定走多重：

- **trivial**——一行真实改动、显然 typo、已有明确步骤的低风险动作。直接做，不拷问、不互审、不写记忆。
- **轻量**——单一关注点、需求清晰、涉及少数文件、低不确定性。直接做或一句话确认即可；可跳过跨模型互审与并行子代理，但完成门禁仍然适用。
- **完整**——跨多文件 / 架构级 / 行为大改 / 明显不确定性。走完整流程：

  1. **读取前询问**——仅在项目历史可能有帮助时询问；授权须说明元数据路由、读取范围和上下文预算，未明确同意就完全跳过。
  2. **拷问需求**——多选优先，互不依赖的小问题合并一次问，挖出隐藏假设、边界条件与成功标准。
  3. **起草方案**——收口需求并做轻量任务拆解。
  4. **呈现方案 + 用户定夺**——把方案交给用户三选：**A 直接开干 / B 先让另一端模型互审再定 / C 修改方案**。仅当选 B 才跑跨模型互审，整合修订版后回到本步重新定夺。互审不自动触发，也不闷头跳过。
  5. **PM 持续调度子代理**——安全的 Ready 工作会在槽位释放后持续补位，无需等待整波完成；写集合冲突或强耦合的工作仍保持串行。
  6. **两阶段审查**——先查规格合规，再查代码质量；不过回炉，最多 2 次，仍不过交回用户定夺。
  7. **完成门禁**——当场跑出验证证据才能宣称「完成 / 通过」。
  8. **写入前询问**——任务终局有可复用事实时，枚举目标文件和事实后单独询问；读取授权不能复用为写入授权。

执行期间，主 PM 保持响应并在 commentary 展示真实进度看板，也能继续接收 `QUERY`、`ADD`、`CHANGE`、`REPLACE`、`PRIORITY` 类新消息。详细协议见 [PM 编排参考](references/pm-orchestration.md) 和 [记忆协议](references/memory.md)。

跨模型互审统一走包装器，方案全文通过 stdin 传递：

```bash
scripts/cross-review.sh codex /path/to/repo < plan.md   # Claude → Codex
scripts/cross-review.sh claude /path/to/repo < plan.md  # Codex → Claude
```

## 跨平台

同一份 skill 契约在两个平台上以各自原生工具落地：

| 动作 | Claude | Codex |
|---|---|---|
| 派并行子代理 | `Task` / `Agent` 工具 | `spawn_agent` |
| 交互式提问 | `AskUserQuestion` | `request_user_input`（可用时）/ 直接追问 |
| 进度跟踪 | `TodoWrite` | `update_plan` |
| 跨模型互审 | `scripts/cross-review.sh codex …` | `scripts/cross-review.sh claude …` |
| 子代理模型 | 工具支持时请求 `STARKS_AGENT_MODEL` | 工具支持时请求，否则继承平台配置 |

## 卸载

```bash
bash scripts/uninstall.sh
```

只移除两个软链，且仅当它们确实指向本源仓时才删；绝不删除或改动源仓文件。预览将做什么而不实际删除：

```bash
DRY_RUN=1 bash scripts/uninstall.sh
```

## 许可证

[MIT](LICENSE)

---

设计细节详见 [`docs/DESIGN.md`](docs/DESIGN.md)。
