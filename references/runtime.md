# starks Runtime Reference

低频且易变的配置、跨模型命令、平台工具映射集中在这里。决策门禁仍以 `SKILL.md` 为准。

## 子代理模型与思考深度

默认继承平台全局默认模型与思考深度，不绑定命名 Agent、固定模型或固定思考强度。用户自己保存的 pi 子代理默认（见“子代理默认模型配置”）属于用户明确配置，不是 skill 写死的绑定。

- 已存用户默认优先：存在 `STARKS_AGENT_MODEL_PI` / `STARKS_AGENT_THINKING_PI` 时，所有派发使用该默认，PM 不得自行偏离；认为某切片需要不同模型或强度时只能向用户建议，征得同意后才可偏离。默认模型从 registry 消失时如实报告，让用户重选或回退继承平台配置。
- 无已存默认时，主 PM 可根据任务复杂度、风险、验证成本和可用能力，自行选择子代理的模型与思考深度；无需为每个切片另行询问，但必须遵守用户明确配置、预算及平台规则。
- 选择只作用于本次派发，不改写平台全局设置或用户的 Agent 配置。没有调整理由时不传覆盖参数。
- 派发前确认工具是否支持模型和思考深度选择，以及候选模型 / Agent 是否实际可用；两种参数分别检查，不假定支持其一就支持另一项。
- pi：有 `subagent` 工具时，先调 `subagent {action:"models"}` 复制会话 registry 中精确的 `provider/id`，思考强度用模型后缀 `provider/id:<强度>`（off/minimal/low/medium/high/xhigh/max）；无该工具则继承平台配置并如实说明。
- 设置入口：`/skill:starks subagents` 设置台随时可用；完整档第 3 步呈现方案且无已存默认时也顺带问一次“子代理模型安排”（继承平台默认 / 现在选择，与互审询问同时出现时合并成一次提问）；选择流程为列 registry → 选精确 `provider/id` → 选思考强度 → 仅本次或存为默认。已有默认不再问；用户可随时要求更改或清除默认（清除即移除 `.env` 对应键）。轻量与 trivial 不派子代理、不询问。
- 只有平台支持时才传入相应参数；不支持或无法确认时继承平台配置，并说明未指定的项。请求值不等于实际生效值；未经返回元数据验证，不声称已验证具体模型或思考深度。
- 派活单注明“继承平台配置”或本次选择与简短理由。不设角色专属的强制等级；实现、探索与审查都按实际任务决策。

## 子代理默认模型配置（pi）

| 变量 | 用途 | 默认 |
|---|---|---|
| `STARKS_AGENT_MODEL_PI` | PM 派发子代理的默认模型（registry 精确的 `provider/id`） | 未设或为空则继承平台全局默认 |
| `STARKS_AGENT_THINKING_PI` | PM 派发子代理的默认思考强度（`off/minimal/low/medium/high/xhigh/max`） | 未设或为空则继承平台全局默认 |

用户在选择流程中同意“存为默认”时写入 skill 根目录 `.env`；优先级是用户本次明确要求 > 已导出值 > `.env` > 继承平台全局默认。两键只作用于 PM 派发的干活子代理，不影响互审 reviewer 的选择；`scripts/cross-review.sh` 不读取它们。

## skill 后缀与设置台

`/skill:starks <args>` 的 args 会以 `User: <args>` 随 skill 送达。环境守卫之后先做后缀判断：去首尾空白、大小写不敏感地精确匹配两个保留后缀；命中进入设置台，其余 args 一律视为任务描述进入正常分档（`/skill:starks 修登录 bug` 这类用法不受影响）。

| 后缀 | 进入 | 管理对象 |
|---|---|---|
| `cross-review` | 互审设置台 | pi：`STARKS_REVIEW_MODEL_PI` / `STARKS_REVIEW_THINKING_PI`；Claude/Codex：`STARKS_REVIEW_MODEL_CODEX` / `STARKS_REVIEW_MODEL_CLAUDE` / `STARKS_REVIEW_TIMEOUT_SECONDS` |
| `subagents` | 子代理设置台 | pi：`STARKS_AGENT_MODEL_PI` / `STARKS_AGENT_THINKING_PI`；Claude/Codex：不支持保存子代理默认，如实说明并展示当前继承规则 |

设置台规则：

- 纯配置操作：不分档、不拷问、不互审、不派代理、不改代码；完成门禁体现为写入后回读 `.env` 确认生效。
- 先展示当前生效值及来源（已导出 > `.env` > 未设置），再给菜单：设置/更改 → 列 registry（`subagent {action:"models"}`，超出提问工具选项上限改用编号清单）选模型 → 选思考强度 → 存为默认；清除默认 → 移除 `.env` 对应键；退出。
- 快捷形式：`<后缀> <provider/id> [强度]` 直接设置并保存。模型须在 registry 中、强度须在 `off/minimal/low/medium/high/xhigh/max` 内；任一非法即报错并列出合法值，不写入。省略强度时保留已存值；无已存值则 reviewer 取 `high`、子代理留空（继承平台）。`<后缀> clear` 清除默认。
- 写 `.env` 只更新或追加对应键，不动其它行；`.env` 已 gitignore，不得提交；写后回读验证。
- Claude/Codex 上无 registry 可列，`cross-review` 设置台的 reviewer 模型名由用户手工输入；`subagents` 设置台只读展示“继承平台全局默认 + PM 按规则自主”。

## 跨模型互审配置

以下变量仅用于跨模型互审 reviewer，不控制 PM 派发的干活子代理（后者的用户默认见“子代理默认模型配置”）：

| 变量 | 用途 | 默认 |
|---|---|---|
| `STARKS_REVIEW_MODEL_CODEX` | Codex reviewer 模型 | 未设则省略 `-m`，使用 Codex 默认 |
| `STARKS_REVIEW_MODEL_CLAUDE` | Claude reviewer 模型 | 未设则省略 `--model`，使用 Claude 默认 |
| `STARKS_REVIEW_TIMEOUT_SECONDS` | 跨模型互审超时秒数 | `600` |
| `STARKS_REVIEW_MODEL_PI` | pi reviewer 模型（registry 中精确的 `provider/id`） | 未设或为空则互审时询问 |
| `STARKS_REVIEW_THINKING_PI` | pi reviewer 思考强度 | 未设或为空则互审时询问（建议 `high`） |

wrapper 读取的三个变量可放在 skill 根目录 `.env`，优先级是已导出值 > `.env` > 表中默认；reviewer 模型的显式空值也优先，并表示不传模型参数。wrapper 未提供思考深度参数，不得声称它已强制设置该项。pi 的两个键由 starks 在用户同意“存为默认”时写入 `.env`（`.env` 已 gitignore，不得提交）；读取优先级同样是已导出值 > `.env` > 无默认（每次询问）。

## 跨模型互审

调用形式：

```bash
scripts/cross-review.sh <codex|claude> [repo-dir] <<'PLAN'
<方案全文>
PLAN
```

方案全文必须走 stdin，不放进命令行参数。Claude 主代理选择 `codex` reviewer；Codex 主代理选择 `claude` reviewer。脚本负责 reviewer prompt、只读权限、`STARKS_CROSS_REVIEW` 防递归、可选模型参数与超时。Codex reviewer 只在一次性空目录中运行，关闭 Shell、子代理、app、联网和图像工具，并禁止子进程继承调用环境；reviewer 只收到方案，不收到目标仓库内容。

脚本返回非零、超时、CLI/模型不可用都表示互审未完成。不得静默跳过：如实报告原因，让用户选择重试、换可用模型，或明确授权本次跳过互审后再回方案确认。

## pi 上的跨模型互审

pi 作为主代理时，互审走 `subagent` 派发的一次性 reviewer，不经过 `scripts/cross-review.sh`（它只调外部 `codex` / `claude` CLI，不能把 pi 当 engine）。固定流程：

1. **是否互审**：仅设计文档或重大变更任务在方案定夺时询问；其余任务默认不互审、不询问；用户任何时刻主动提出互审都直接进入本流程。
2. **选模型**：调 `subagent {action:"models"}` 列出会话 registry，让用户选精确的 `provider/id`；建议与当前会话模型不同才是真跨模型，用户坚持同模型时如实说明后照办。模型超过提问工具选项上限时，改用编号文本清单让用户回复序号或 id。
3. **选思考强度**：`off/minimal/low/medium/high/xhigh/max`，评审建议 `high`。
4. **存默认**：询问是否保存为默认互审设置；同意则把 `STARKS_REVIEW_MODEL_PI` 与 `STARKS_REVIEW_THINKING_PI` 写入 skill 根目录 `.env`。已有默认时，互审前先展示当前默认（模型 + 强度），让用户选“用默认 / 本次更换 / 修改默认”。用户随时可要求修改默认互审模型或思考强度：重走第 2、3 步并写回 `.env`，或用 `/skill:starks cross-review` 设置台管理。
5. **派发**：`subagent` 用 `reviewer` agent（只读工具集；无则选只读等价 agent）、`context:"fresh"`、`model:"provider/id:强度"`；task = `prompts/cross-review.md` 全文 + `\n\n--- BEGIN UNTRUSTED PLAN DATA ---\n` + 方案全文，并要求只输出评审意见。reviewer 不得再派代理、不得调用 skill；pi 路径的防递归靠 reviewer prompt 与只读工具集，外部 wrapper 的 `STARKS_CROSS_REVIEW` 守卫保持不变。
6. **失败**：子代理报错、超时或结果不可用即互审未完成，按 `SKILL.md` 的失败处置执行，不得伪造评审意见。

## 平台工具映射（Claude / Codex / pi）

| 动作 | Claude | Codex | pi |
|---|---|---|---|
| 派子代理 | `Task` / `Agent` | `spawn_agent`（可用时） | `subagent`（pi-subagents；无则顺序执行） |
| 等结果 | 工具自动返回或平台 wait | `wait_agent` / 平台释放机制 | 原生完成通知；无通知的后台工作用 `bg_wait` |
| 追补收工小票 | 平台 resume / follow-up（可用时） | `followup_task` / 平台同类机制（可用时） | `subagent {action:"resume"}` |
| 进度 | `TodoWrite` | `update_plan` | `todo` |
| 提问 | `AskUserQuestion` | `request_user_input`（可用时）或直接追问 | `ask_user_question` 或直接追问 |
| 跨模型互审 | `scripts/cross-review.sh codex [repo-dir]` | `scripts/cross-review.sh claude [repo-dir]` | `subagent` 派发 reviewer（见上节） |

派发时只传 `references/pm-orchestration.md` 定义的“派活单 + 随身小抄”，不传完整 session。平台显式支持能力限制、隔离 worktree 或 follow-up 时才使用对应参数；否则把能力边界写入派活单、写冲突改为串行，并如实说明没有建立原生沙箱或隔离。可选 skill 或工具不可用时，采用不改变核心门禁的可用替代方案；不得伪造调用或结果。

完整档的依赖图、持续填槽、用户看板与动态接单协议见 `references/pm-orchestration.md`。
