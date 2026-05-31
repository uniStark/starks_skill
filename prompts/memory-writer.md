你的任务：把本次完成的工作沉淀成 Obsidian 项目记忆。只写文件，不做别的。

硬约束（违反即失败）：
- 若设置了 `$STARKS_STYLE_NOTE`，先读它学你的笔风后再写；未设置就跳过这步。
- 写得短、贴你的风格，不要通用 AI 模板腔。
- 绝不读 / 写记忆库里的 `private/` 区（即 `$STARKS_MEMORY_DIR` 同级的 `private/`）及其任何子路径。
- 不要调用 skill、不要派子代理、不要触发 starks。
- 本机有 hook 会拦子代理用 Write 等文件写工具写文件；**一律用 shell 写入**（如 `cat > "$f" <<'EOF' … EOF`），不要用 Write 工具。

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
