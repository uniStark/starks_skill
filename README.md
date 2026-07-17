<h1 align="center">starks</h1>

<p align="center">
  Turn a rough request into verified delivery — adaptive task tiers, optional Claude↔Codex plan review, lean PM-mode sub-agents, and evidence before “done.”
</p>

<p align="center">
  English | <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/uniStark/starks_skill/releases"><img src="https://img.shields.io/github/v/release/uniStark/starks_skill" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/Claude%20Code-skill-8A2BE2" alt="Claude Code">
  <img src="https://img.shields.io/badge/Codex-skill-10A37F" alt="Codex">
</p>

## Why starks?

Most agent workflows are either too casual for a large change or too ceremonial for a small one. starks adapts: tiny edits stay tiny, while complex work gets requirement grilling, an explicit plan gate, PM orchestration, two-stage review, and fresh verification.

Its distinctive move is at the plan boundary: **you** decide whether Claude and Codex should challenge each other's thinking before implementation. During execution, a responsive PM keeps child agents focused with small, one-way context packs instead of making every agent reread the entire project history.

## Signature features

- **Task tiering** — trivial / light / full modes scale the process to the risk. Simple work stays fast; only genuine complexity pays for the full workflow.
- **Cross-model review (you choose)** — at the hard plan gate, choose **start now / ask the other model / revise**. Claude↔Codex review is never automatic and never silently skipped.
- **Work-conserving scheduling** — a dependency DAG and Ready queue fill open slots as soon as safe work appears. Strongly coupled slices stay sequential instead of being split for vanity parallelism.
- **Lean sub-agents** — the PM sends each flat child a compact **“派活单 + 随身小抄”** (work order + context cheat sheet). Children do not reload the session, shared memory, general project docs, or recent commits; they return one bounded **“收工小票”** (completion receipt).
- **Truthful status board** — the PM stays responsive, shows real state rather than invented percentages or ETAs, and keeps accepting `QUERY`, `ADD`, `CHANGE`, `REPLACE`, and `PRIORITY` while execution continues.
- **Two-stage review** — spec compliance comes first, code quality second. Failed slices go back for bounded rework instead of disappearing into a vague “done.”
- **Verification gate** — no “done / passing / fixed” claim without freshly-run evidence that matches the acceptance criteria.
- **Scoped shared memory** — Claude and Codex can share cross-project Obsidian facts without auto-loading a vault. Reads are opt-in, scoped, and budgeted; writes need separate, enumerated approval; routing prefers a sanitized stable `repo_id`.
- **Dual-platform, recursion-safe** — one `SKILL.md` serves Claude Code and Codex. A cross-reviewer answers once and exits instead of invoking starks again.

## The signature PM loop

```text
request
  └─ task tier → requirement grill → plan
                                  └─ you choose: start / cross-review / revise
                                                   │
PM: dependency DAG + Ready queue                    │ optional Claude↔Codex pass
  ├─ 派活单 + 随身小抄 → flat child A ─┐            │
  ├─ 派活单 + 随身小抄 → flat child B ─┼─→ 收工小票 ─┘
  └─ keep the board live + accept new user input ──→ spec review → code review → verification
```

The PM is the only context-convergence point. A child gets its goal, allowed files, direct dependencies, constraints, acceptance criteria, and expected evidence—not the full conversation. It may inspect named targets, required direct dependencies, and mandatory project rules; if something is missing, it reports **缺料** rather than expanding scope on its own. Only the PM may spawn children, so the agent tree stays one level deep and predictable.

Every child closes with a compact receipt:

```text
【收工小票】
- 收工状态：已交卷 / 缺料 / 等老板拍板 / 翻车
- 动了什么：...
- 验收证据：...
- 留下的雷：...
- 产物位置：...
- 建议下一棒：...
```

That receipt feeds the live board and review queue without dumping raw logs, long diffs, or duplicate project context back into the PM.

## Requirements

- Claude Code **or** Codex CLI
- `bash`
- `python3` (process-group timeout runner)
- macOS or Linux
- Cross-model review needs the *other* engine's CLI on your `PATH` (`claude` / `codex`)
- Optional: a knowledge base such as Obsidian for the memory step; `gh` (maintenance only)
- Recommended: the [superpowers](https://github.com/obra/superpowers) plugin — starks hands off to its `systematic-debugging` / `writing-skills` / `brainstorming` skills when those situations arise (works fine without it; those hand-offs just won't fire)

## Installation

```bash
bash scripts/install.sh
```

This symlinks the repo into `~/.claude/skills/starks` and `~/.codex/skills/starks`, so both engines share the same `SKILL.md`. Existing files or symlinks pointing elsewhere are left untouched.

## Configuration

starks reads a few optional environment variables (all have defaults or degrade gracefully):

| Env var | What | Default |
|---|---|---|
| `STARKS_AGENT_MODEL` | requested sub-agent model when the platform exposes model selection | inherit platform configuration |
| `STARKS_REVIEW_MODEL_CODEX` | reviewer model when Codex reviews the plan (Claude→Codex) | unset → codex default |
| `STARKS_REVIEW_MODEL_CLAUDE` | reviewer model when Claude reviews the plan (Codex→Claude) | unset → claude default |
| `STARKS_REVIEW_TIMEOUT_SECONDS` | cross-review timeout in seconds | `600` |
| `STARKS_MEMORY_DIR` | shared project-memory root (e.g. an Obsidian vault subfolder); configuration only makes scoped opt-in available | unset |
| `STARKS_STYLE_NOTE` | optional note the memory writer reads first to match your style | unset |

Export sub-agent and memory settings into the primary agent process. Reviewer settings may also live in `.env`; `scripts/cross-review.sh` reads them automatically and already-exported values take precedence.

## How it works

starks doesn't run the same heavyweight pipeline on everything. When real work starts, it first tiers the task:

- **trivial** — a one-line real change, an obvious typo, or a low-risk action with an already-known procedure. Just do it: no grilling, no review, no memory.
- **light** — a single clear concern across a few files. Do it (or confirm in one line) and skip the parallel / cross-review machinery, but the verification gate still applies.
- **full** — multi-file, architectural, large behavior change, or genuinely uncertain. This runs the whole flow.

For a full-tier task the flow is: **ask whether to route shared project memory** when history may help (default: skip; the task-scoped approval names the metadata scan, files, and context budget) → **grill** the requirements — multiple-choice first, batching independent questions — to surface hidden assumptions, edges, and success criteria → **draft** a plan → **present it for one decision** (a hard gate: start now / cross-review first / revise). Only if you pick cross-review does the plan go to the other model; the revised version comes back for sign-off. After approval the PM uses work-conserving scheduling, gives each flat child agent a minimal work order/context pack, accepts only a bounded completion receipt, runs the **two-stage review**, and holds the **verification gate**. At task end, reusable facts are offered as a separate, enumerated write; read approval never implies write approval. See the [PM orchestration reference](references/pm-orchestration.md) and [memory protocol](references/memory.md) for details.

Cross-review uses one stable wrapper; the full plan always travels over stdin:

```bash
scripts/cross-review.sh codex /path/to/repo < plan.md   # Claude → Codex
scripts/cross-review.sh claude /path/to/repo < plan.md  # Codex → Claude
```

## Cross-platform

One skill, two engines — starks maps each step to the platform's native tools.

| Action | Claude | Codex |
|---|---|---|
| Spawn parallel sub-agents | `Task` / `Agent` | `spawn_agent` |
| Track progress | `TodoWrite` | `update_plan` |
| Cross-model review | `scripts/cross-review.sh codex …` | `scripts/cross-review.sh claude …` |
| Select sub-agent model | request `STARKS_AGENT_MODEL` when supported | request it when supported; otherwise inherit platform config |

## Uninstall

```bash
bash scripts/uninstall.sh
```

Removes only the two symlinks, and only when they actually point at this repo (symlinks pointing elsewhere, or non-symlinks, are skipped). The source repo is never touched. Preview without removing:

```bash
DRY_RUN=1 bash scripts/uninstall.sh
```

## License

MIT

---

See [`docs/DESIGN.md`](docs/DESIGN.md) for the design rationale.
