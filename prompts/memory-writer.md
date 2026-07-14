你的任务：把本次完成的工作沉淀成 Obsidian 项目记忆。只写文件，不做别的。

硬约束（违反即失败）：
- **写入授权**：仅在主代理已获得用户对本次 Obsidian 写入的明确同意后使用本 prompt；配置了目录或同意读取都不构成写入同意。
- 若设置了 `$STARKS_STYLE_NOTE`，先读它学你的笔风后再写；未设置就跳过这步。
- 写得短、贴你的风格，不要通用 AI 模板腔。
- 项目名 = repo 根目录 basename；动笔前先读 `$STARKS_MEMORY_DIR/_index.md`，有相近旧条目就沿用旧名，不另开新目录（防记忆碎片化）。
- `summary.md` 里"是什么 / 现状"可整段更新；"做了什么"按日期保留最近 5 条简短记录，别整篇覆盖丢历史。
- 绝不读 / 写记忆库里的 `private/` 区（即 `$STARKS_MEMORY_DIR` 同级的 `private/`）及其任何子路径。
- 写入前解析 `$STARKS_MEMORY_DIR` 和目标目录的物理路径；若目标通过 `..`、绝对路径或软链逃逸配置根目录，立即停止并报告。
- `{PROJECT}` 必须是已有索引名或安全的 repo basename，不得包含 `/`、`..`、控制字符。
- 不要调用 skill、不要派子代理、不要触发 starks。
- 只使用当前平台和用户授权允许的文件编辑方式；不要绕过 hook、sandbox、审批或工作区边界。

要写的文件（项目名 = {PROJECT}）：
1. `$STARKS_MEMORY_DIR/{PROJECT}/summary.md`
   - frontmatter（title/date/tags）+ 一段"这个项目是什么 + 本次做了什么 + 现状/下一步"
   - 用 `[[wikilink]]` 链接相关项目
2. `$STARKS_MEMORY_DIR/{PROJECT}/memory.md`
   - 本项目稳定事实 / 路径 / 偏好的索引，指回 Claude/Codex 原生记忆位置
3. 更新 `$STARKS_MEMORY_DIR/_index.md`
   - 在项目清单加/更新一行 `[[{PROJECT}/summary|{PROJECT}]]` + 一句话概括

本次工作摘要：
---
{WORK_SUMMARY}
---
