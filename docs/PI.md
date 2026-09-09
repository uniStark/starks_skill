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

## pi 的能力边界

pi 默认提供 `read`、`write`、`edit` 和 `bash`，不内置：

- sub-agent；
- plan mode；
- TodoWrite / update_plan；
- 后台 bash；
- 原生并发调度。

因此 starks 在 pi 中采用顺序降级：

1. 任务分档；
2. 完整任务先澄清需求并呈现方案；
3. 等待用户明确批准；
4. 顺序执行切片；
5. 依次进行 spec review 和 code review；
6. 运行最终验证。

完整任务需要长期可见进度时，可选择创建：

```text
.starks/plan.md
.starks/board.md
```

trivial 和轻量任务不应为了流程而创建这些文件。

## 模型与思考深度

starks 不绑定固定子代理模型、角色或思考强度：

- 默认继承 pi / 当前平台的全局配置；
- 如果安装了提供子代理能力的 extension，主 PM 可按任务风险自行决定模型和 thinking；
- 只有扩展明确支持时才传递覆盖参数；
- 不修改全局设置；
- 未经运行时元数据确认，不声称具体模型或 thinking 已生效。

## 跨模型互审

`scripts/cross-review.sh` 只能调用外部 `codex` 或 `claude` CLI：

```bash
scripts/cross-review.sh codex /path/to/repo < plan.md
scripts/cross-review.sh claude /path/to/repo < plan.md
```

pi 不能作为该 wrapper 的 engine。若两个外部 CLI 都不可用，必须向用户说明互审不可用，不能假装已完成。

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
