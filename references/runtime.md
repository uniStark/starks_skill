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
| 追补收工小票 | 平台 resume / follow-up（可用时） | `followup_task` / 平台同类机制（可用时） |
| 进度 | `TodoWrite` | `update_plan` |
| 提问 | `AskUserQuestion` | `request_user_input`（可用时）或直接追问 |
| 跨模型互审 | `scripts/cross-review.sh codex [repo-dir]` | `scripts/cross-review.sh claude [repo-dir]` |

派发时只传 `references/pm-orchestration.md` 定义的“派活单 + 随身小抄”，不传完整 session。平台显式支持能力限制、隔离 worktree 或 follow-up 时才使用对应参数；否则把能力边界写入派活单、写冲突改为串行，并如实说明没有建立原生沙箱或隔离。可选 skill 或工具不可用时，采用不改变核心门禁的可用替代方案；不得伪造调用或结果。

完整档的依赖图、持续填槽、用户看板与动态接单协议见 `references/pm-orchestration.md`。

## 项目记忆入口

配置 `STARKS_MEMORY_DIR` 只表示共享记忆功能可用，不触发任何读取、搜索、列举或写入。用户同意本任务读取后，主代理按 `prompts/memory-reader.md` 执行；预算、跨项目路由、frontmatter schema、旧文件兼容和安全边界见 `references/memory.md`。

读取授权与写入授权相互独立。任务终局若有可复用事实，主代理按 `prompts/memory-writer.md` 枚举目标与内容并另行询问；只有用户明确同意且平台规则允许才写入。`STARKS_STYLE_NOTE` 只在本次写入获批后读取。失败要报告，不得扩大授权范围。
