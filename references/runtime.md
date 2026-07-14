# starks Runtime Reference

低频且易变的配置、跨模型命令、平台工具映射和项目记忆入口集中在这里。决策门禁仍以 `SKILL.md` 为准。

## 配置

| 变量 | 用途 | 默认 |
|---|---|---|
| `STARKS_AGENT_MODEL` | 平台支持显式选择时，请求子代理模型 | 未设则继承平台配置 |
| `STARKS_REVIEW_MODEL_CODEX` | Codex reviewer 模型 | 未设则省略 `-m`，使用 Codex 默认 |
| `STARKS_REVIEW_MODEL_CLAUDE` | Claude reviewer 模型 | 未设则省略 `--model`，使用 Claude 默认 |
| `STARKS_REVIEW_TIMEOUT_SECONDS` | 跨模型互审超时秒数 | `600` |
| `STARKS_MEMORY_DIR` | 项目记忆根目录 | 未设则不提供记忆读写选项 |
| `STARKS_STYLE_NOTE` | memory writer 可选文风笔记 | 未设则不读取 |

`STARKS_AGENT_MODEL`、`STARKS_MEMORY_DIR`、`STARKS_STYLE_NOTE` 需导出到主代理进程，优先级是已导出值 > 表中默认。两个 reviewer 模型变量与 timeout 还可放在 skill 根目录 `.env`，优先级是已导出值 > `.env` > 表中默认；reviewer 模型的显式空值也优先，并表示不传模型参数。`STARKS_AGENT_MODEL` 只能在当前平台工具支持显式模型选择时请求；不支持时继承平台配置，不得声称已强制或验证该模型。

## 跨模型互审

调用形式：

```bash
scripts/cross-review.sh <codex|claude> [repo-dir] <<'PLAN'
<方案全文>
PLAN
```

方案全文必须走 stdin，不放进命令行参数。Claude 主代理选择 `codex` reviewer；Codex 主代理选择 `claude` reviewer。脚本负责 reviewer prompt、只读权限、`STARKS_CROSS_REVIEW` 防递归、可选模型参数与超时。

脚本返回非零、超时、CLI/模型不可用都表示互审未完成。不得静默跳过：如实报告原因，让用户选择重试、换可用模型，或明确授权本次跳过互审后再回方案确认。

## Claude / Codex 工具映射

| 动作 | Claude | Codex |
|---|---|---|
| 派子代理 | `Task` / `Agent` | `spawn_agent` |
| 等结果 | 工具自动返回或平台 wait | `wait_agent` / 平台释放机制 |
| 进度 | `TodoWrite` | `update_plan` |
| 提问 | `AskUserQuestion` | `request_user_input`（可用时）或直接追问 |
| 跨模型互审 | `scripts/cross-review.sh codex [repo-dir]` | `scripts/cross-review.sh claude [repo-dir]` |

工具支持隔离 worktree 时可用于解决写集合冲突；否则顺序执行。可选 skill 或工具不可用时，如实说明限制，采用不改变核心门禁的可用替代方案；不得伪造调用或结果。

完整档的依赖图、持续填槽、用户看板与动态接单协议见 `references/pm-orchestration.md`。

## 项目记忆入口

配置 `STARKS_MEMORY_DIR` 只表示记忆功能可用，不会自动读取或写入。主代理不得为了判断是否值得询问而预读 `_index.md`；只有用户对本次读取明确同意后，才以 repo 根目录 basename 作为项目名，先读 `$STARKS_MEMORY_DIR/<project>/summary.md`，摘要不足时按需读 `memory.md`，没有同名目录时才查 `_index.md`。

读取授权与写入授权相互独立。有实质、可复用进展时，主代理另行询问是否写入；只有用户对本次写入明确同意且平台规则允许，才通过当前平台规定的 memory writer 入口写入，内容与格式遵循 `prompts/memory-writer.md`，并在 `STARKS_STYLE_NOTE` 已配置且可读时读取文风笔记。未明确同意就跳过，失败要报告，并且绝不读取、写入或修改 `private/`。
