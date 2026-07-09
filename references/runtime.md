# starks Runtime Reference

低频且易变的配置、跨模型命令、平台工具映射和项目记忆入口集中在这里。决策门禁仍以 `SKILL.md` 为准。

## 配置

| 变量 | 用途 | 默认 |
|---|---|---|
| `STARKS_AGENT_MODEL` | 平台支持显式选择时，请求子代理模型 | 未设则继承平台配置 |
| `STARKS_REVIEW_MODEL_CODEX` | Codex reviewer 模型 | 未设则省略 `-m`，使用 Codex 默认 |
| `STARKS_REVIEW_MODEL_CLAUDE` | Claude reviewer 模型 | 未设则省略 `--model`，使用 Claude 默认 |
| `STARKS_REVIEW_TIMEOUT_SECONDS` | 跨模型互审超时秒数 | `600` |
| `STARKS_MEMORY_DIR` | 项目记忆根目录 | 未设则跳过项目记忆 |
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

## 项目记忆入口

项目名默认取 repo 根目录 basename；先查 `$STARKS_MEMORY_DIR/<project>/summary.md` 与 `memory.md`，没有同名目录时查 `$STARKS_MEMORY_DIR/_index.md`。写入通过当前平台规定的 memory writer 入口，内容与格式遵循 `prompts/memory-writer.md`；`STARKS_STYLE_NOTE` 已配置且可读时先读文风笔记。

只有平台规则允许且用户已授权时才能写项目记忆；配置目录不构成授权。只记录实质、可复用进展，写失败就报告，并且绝不读取、写入或修改 `private/`。
