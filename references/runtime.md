# starks Runtime Reference

低频且易变的配置、跨模型命令、平台工具映射集中在这里。决策门禁仍以 `SKILL.md` 为准。

## 子代理模型与思考深度

默认继承平台全局默认模型与思考深度，不绑定命名 Agent、固定模型或固定思考强度，也不设置 skill 专用的子代理模型环境变量。

- 主 PM 可根据任务复杂度、风险、验证成本和可用能力，自行选择子代理的模型与思考深度；无需为每个切片另行询问，但必须遵守用户明确配置、预算及平台规则。
- 选择只作用于本次派发，不改写平台全局设置或用户的 Agent 配置。没有调整理由时不传覆盖参数。
- 派发前确认工具是否支持模型和思考深度选择，以及候选模型 / Agent 是否实际可用；两种参数分别检查，不假定支持其一就支持另一项。
- 只有平台支持时才传入相应参数；不支持或无法确认时继承平台配置，并说明未指定的项。请求值不等于实际生效值；未经返回元数据验证，不声称已验证具体模型或思考深度。
- 派活单注明“继承平台配置”或本次选择与简短理由。不设角色专属的强制等级；实现、探索与审查都按实际任务决策。

## 跨模型互审配置

以下变量仅用于 `scripts/cross-review.sh` 调用的外部 reviewer，不控制 PM 派发的子代理：

| 变量 | 用途 | 默认 |
|---|---|---|
| `STARKS_REVIEW_MODEL_CODEX` | Codex reviewer 模型 | 未设则省略 `-m`，使用 Codex 默认 |
| `STARKS_REVIEW_MODEL_CLAUDE` | Claude reviewer 模型 | 未设则省略 `--model`，使用 Claude 默认 |
| `STARKS_REVIEW_TIMEOUT_SECONDS` | 跨模型互审超时秒数 | `600` |

两个 reviewer 模型变量与 timeout 可放在 skill 根目录 `.env`，优先级是已导出值 > `.env` > 表中默认；reviewer 模型的显式空值也优先，并表示不传模型参数。wrapper 未提供思考深度参数，不得声称它已强制设置该项。

## 跨模型互审

调用形式：

```bash
scripts/cross-review.sh <codex|claude> [repo-dir] <<'PLAN'
<方案全文>
PLAN
```

方案全文必须走 stdin，不放进命令行参数。Claude 主代理选择 `codex` reviewer；Codex 主代理选择 `claude` reviewer。脚本负责 reviewer prompt、只读权限、`STARKS_CROSS_REVIEW` 防递归、可选模型参数与超时。Codex reviewer 只在一次性空目录中运行，关闭 Shell、子代理、app、联网和图像工具，并禁止子进程继承调用环境；reviewer 只收到方案，不收到目标仓库内容。

脚本返回非零、超时、CLI/模型不可用都表示互审未完成。不得静默跳过：如实报告原因，让用户选择重试、换可用模型，或明确授权本次跳过互审后再回方案确认。

## Claude / Codex 工具映射

| 动作 | Claude | Codex |
|---|---|---|
| 派子代理 | `Task` / `Agent` | `spawn_agent`（可用时） |
| 等结果 | 工具自动返回或平台 wait | `wait_agent` / 平台释放机制 |
| 追补收工小票 | 平台 resume / follow-up（可用时） | `followup_task` / 平台同类机制（可用时） |
| 进度 | `TodoWrite` | `update_plan` |
| 提问 | `AskUserQuestion` | `request_user_input`（可用时）或直接追问 |
| 跨模型互审 | `scripts/cross-review.sh codex [repo-dir]` | `scripts/cross-review.sh claude [repo-dir]` |

派发时只传 `references/pm-orchestration.md` 定义的“派活单 + 随身小抄”，不传完整 session。平台显式支持能力限制、隔离 worktree 或 follow-up 时才使用对应参数；否则把能力边界写入派活单、写冲突改为串行，并如实说明没有建立原生沙箱或隔离。可选 skill 或工具不可用时，采用不改变核心门禁的可用替代方案；不得伪造调用或结果。

完整档的依赖图、持续填槽、用户看板与动态接单协议见 `references/pm-orchestration.md`。
