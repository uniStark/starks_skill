---
name: starks
description: Use when starting real work — building a feature, adding or changing functionality, refactoring, or orchestrating a multi-step task（开发新功能 / 改功能 / 重构 / 多步骤任务 / 起新活）. Not for bug/debugging (→ systematic-debugging) or writing/editing a skill (→ writing-skills).
---

# starks — 任务启动器

## Overview

先按任务分档决定走多重：简单任务直接做，复杂任务才走完整流程。完整档质量优先；trivial / 轻量保持低开销。

以下操作前先读 `references/runtime.md`：

- 配置 starks；
- 实际运行跨模型互审；
- 映射 Claude / Codex 平台工具；
- 执行项目记忆。

核心决策规则以本文件为准。

完整档的依赖图、持续调度、进度看板与动态接单细则见 `references/pm-orchestration.md`。

## 环境守卫（最先检查）

若 `STARKS_CROSS_REVIEW` 已设置，你是一次性 reviewer：

- 不进入 starks 流程；
- 不调用任何 skill；
- 不派子代理，也不反向调用模型；
- 只对收到的方案做“补充 + 纠错”，输出批判性意见后结束。

## 任务分档

| 档位 | 判定 | 执行 |
|---|---|---|
| **trivial** | 一行真实改动、显然 typo、已有明确步骤的低风险动作 | 直接做；不拷问、不互审、不写记忆。 |
| **轻量** | 单一关注点、需求清晰、少数文件、低不确定性 | 直接做或一句确认；可跳过互审与并行；完成门禁仍适用，通过后有实质进展才更新记忆。 |
| **完整** | 跨多文件、架构级、行为大改或明显不确定性 | 执行 HARD-GATE 与七步 Checklist。 |

拿不准就往上靠一档。

## 全局规则与专用 skill

- **完成门禁**：任何档位都必须先取得当场验证证据；无证据不得宣称“完成 / 通过 / 修好”。
- **记忆唤醒**：除 trivial 外，若配置了 `STARKS_MEMORY_DIR` 且存在 `<项目>/`，动手或拷问前读 `summary.md` + `memory.md`；没有同名项目就查 `_index.md`。已有答案不再问用户，旧快照中的路径与约定须现场复核。
- bug、测试失败、非预期行为 → `systematic-debugging`；写或改 skill → `writing-skills`；超大或高不确定设计 → 先 `brainstorming`，完成设计后再回 starks。

## <HARD-GATE>（仅完整档）

完整档必须同时遵守：

- 需求未敲定、用户未明确确认方案前，禁止派子代理写代码；
- 用户确认前禁止落地实现；
- 互审不是硬前提，但必须在第 3 步交由用户三选，用户选 A 才放行。

## 完整档 Checklist

有 TodoWrite / `update_plan` 就跟踪以下七步，没有则跳过工具但不跳过步骤：

1. **拷问 grill** — 先记忆唤醒、读相关文件与近期 commit，再集中提问隐藏假设、边界和成功标准；只问会改变后续走向的问题。
2. **起草方案** — 收口需求并拆解任务，不另造冗长 plan 文件。
3. **呈现方案 + 一次定夺** — 让用户选 **A 直接开干 / B 先让另一个模型（Claude↔Codex）互审再定 / C 改方案**。仅 B 运行互审，整合修订后回到本步再次定夺；不得自动互审或闷头跳过不提。
4. **PM 编排** — 维护依赖图与 `Ready` 队列；有安全任务且可用并发槽位空闲就立即补位，不等待整波。并行写集合必须互斥，冲突时顺序执行或使用隔离 worktree；不得为追求代理数量硬拆任务。
5. **两阶段审查** — 先按 `prompts/spec-review.md` 查 spec 合规，再按 `prompts/code-review.md` 查代码质量；不过就回炉，最多回炉 2 次，仍不过则报告卡点并让用户定夺。
6. **完成门禁** — 当场运行能证明验收标准的完整验证，读清结果后才可作完成声明。
7. **记忆收尾** — 仅有实质可复用进展时执行；只有平台规则与用户授权都允许才可写入，且绝不碰 `private/`。

## 跨模型互审

仅当用户在第 3 步选 B 时：

- 使用 `scripts/cross-review.sh <codex|claude> [repo-dir]`，方案全文走 stdin；
- 脚本非零即互审未完成，须如实说明原因；
- 让用户选择重试、换可用模型或明确授权本次跳过，不得静默跳过并假装通过。实际命令、引擎方向和配置见 `references/runtime.md`。

## PM 与审查边界

- 子代理 prompt 必须 focused、self-contained，并写清 focused goal、write ownership、output 与 acceptance；
- 平台支持显式模型参数时才请求 `STARKS_AGENT_MODEL`，否则继承平台配置并如实说明；
- 主 PM 须保持响应：存在可委派任务时不长期占用大块实现，并在 commentary 展示真实看板，不虚构百分比或 ETA；
- 用户变更已批准的计划、架构或验收标准时，只暂停受影响切片，并重新打开 HARD-GATE；
- 各切片完成后进入两阶段审查，整体验证门禁是唯一汇合点。

## 记忆边界

- 未配置 `STARKS_MEMORY_DIR` 就跳过项目记忆；
- 已配置也不等于获得写入授权；
- 仅在平台规则与用户授权允许时，通过平台规定的 memory writer 入口写入；
- 失败要报告，绝不碰 `private/`。具体入口、路径与降级规则见 `references/runtime.md` 和 `prompts/memory-writer.md`。

## 红旗清单

| 红旗 | 立即处置 |
|---|---|
| 把完整档降成轻量以绕过确认 | 重新分档；完整档回到 HARD-GATE。 |
| 自动跑互审、完全不提互审，或失败后静默略过 | 回到用户三选；失败明确报告并重新授权。 |
| 超出可用槽位、并行写集合相撞，或伪称指定了不受支持的模型 | 缩小并行、隔离写集，并如实说明平台能力。 |
| 没验证就说“应该没问题 / 已完成” | 回到完成门禁，取得新鲜证据。 |
| 未经平台规则与用户授权写记忆，或触碰 `private/` | 停止写入并报告；不得绕过权限。 |
