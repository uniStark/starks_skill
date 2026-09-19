# 在 pi 中使用 starks

## 安装

pi 会从以下全局目录发现 skill：

```text
~/.agents/skills/
~/.pi/agent/skills/
```

在仓库根目录运行：

```bash
bash scripts/install.sh
```

默认安装会创建：

```text
~/.agents/skills/starks -> 当前仓库
```

安装脚本还会处理 Claude / Codex 的兼容入口，但不会覆盖指向其它目录的文件或软链接，也不会修改 pi 的认证、模型、settings、extensions 或项目 trust 配置。

检查安装：

```bash
ls -l ~/.agents/skills/starks
pi --help
```

也可以不安装，临时显式加载：

```bash
pi --skill /path/to/starks_skill
```

## 使用

启动 pi 后执行：

```text
/skill:starks
```

或者直接描述开发任务；pi 会根据 skill 的 description 判断是否加载。Skill 内容会在命中后按需读取 reference，这就是渐进式披露。

两个保留后缀直接进入设置台（仅配置，不分档、不派代理）：

```text
/skill:starks cross-review     # 互审默认：查看 / 设置 / 更改 / 清除
/skill:starks subagents        # 子代理默认：查看 / 设置 / 更改 / 清除
```

其余后缀（如 `/skill:starks 修登录 bug`）视为任务描述，正常分档。设置台细则见 `references/runtime.md`。

## 能力探测与降级

pi 的能力取决于版本与已装扩展，每次会话按实际可用工具判断，不凭假设：

- 有 `subagent` 工具（pi-subagents）：走完整 PM 编排——按 `references/pm-orchestration.md` 派发派活单、等结果（异步运行有原生完成通知；无通知的后台工作用 `bg_wait`）、追补收工小票（`subagent {action:"resume"}`）、保持工作保持型调度。
- 有 `todo`：用它跟踪六步 Checklist；没有则跳过工具但不跳过步骤。
- 有 `ask_user_question`：方案定夺与互审设置用它提问；选项超过上限（如模型清单过长）时改用编号文本清单让用户回复序号或 id。
- 以上都没有：顺序降级——任务分档；完整任务先澄清需求并呈现方案；等待用户明确批准；顺序执行切片；依次进行 spec review 和 code review；运行最终验证。

完整任务需要长期可见进度时，可选择创建：

```text
.starks/plan.md
.starks/board.md
```

trivial 和轻量任务不应为了流程而创建这些文件。

## 模型与思考深度

starks 不绑定固定子代理模型、角色或思考强度：

- 默认继承 pi / 当前平台的全局配置；
- 用户可通过 `/skill:starks subagents` 设置台（或完整档第 3 步的顺带一问）保存默认子代理模型与思考强度（`.env` 的 `STARKS_AGENT_MODEL_PI` / `STARKS_AGENT_THINKING_PI`）；已存默认对所有派发有约束，PM 只能建议偏离；可随时更改或清除；
- 无已存默认且有 `subagent` 工具时，主 PM 可按任务风险自行决定本次派发的模型和 thinking：先调 `subagent {action:"models"}`，复制会话 registry 中精确的 `provider/id`，思考强度用模型后缀（`provider/id:off|minimal|low|medium|high|xhigh|max`）；
- 不修改全局设置；未经运行时元数据确认，不声称具体模型或 thinking 已生效；
- 无 `subagent` 工具时继承平台配置，并如实说明未能指定的项。

## 跨模型互审

pi 作为主代理时，互审由 `subagent` 派发的一次性 reviewer 完成，固定流程与失败处置见 `references/runtime.md` 的“pi 上的跨模型互审”。要点：

- **触发**：仅设计文档或重大变更任务在方案定夺时询问是否互审；其余任务默认不互审、不询问；用户随时可主动提出互审。
- **选模型**：从 pi 会话 registry（`subagent {action:"models"}`）中选精确的 `provider/id`，建议与当前会话模型不同。
- **选思考强度**：`off/minimal/low/medium/high/xhigh/max`，评审建议 `high`。
- **存默认**：用户同意后把默认互审模型与思考强度写入 skill 根目录 `.env` 的 `STARKS_REVIEW_MODEL_PI` / `STARKS_REVIEW_THINKING_PI`；随时可用 `/skill:starks cross-review` 设置台更改或清除。
- **派发**：`reviewer` agent（只读工具集）+ `context:"fresh"`，task 为 `prompts/cross-review.md` 全文加方案全文；reviewer 不再派代理、不调 skill。

`scripts/cross-review.sh` 只能调用外部 `codex` 或 `claude` CLI，pi 不能作为该 wrapper 的 engine：

```bash
scripts/cross-review.sh codex /path/to/repo < plan.md
scripts/cross-review.sh claude /path/to/repo < plan.md
```

仅在需要外部引擎互审、或 pi 无 `subagent` 工具时使用 wrapper。若外部 CLI 与 `subagent` 都不可用，必须向用户说明互审不可用，不能假装已完成。

## 安装副本验证

修改 skill 后重新执行：

```bash
bash scripts/install.sh
```

然后确认安装副本读取的是当前仓库：

```bash
readlink ~/.agents/skills/starks
cmp -s SKILL.md ~/.agents/skills/starks/SKILL.md
```

如果使用 `CODEX_HOME`，Codex 入口位于：

```text
$CODEX_HOME/skills/starks
```
