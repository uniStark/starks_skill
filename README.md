<h1 align="center">starks</h1>

<p align="center">
  A task-launcher skill for Claude Code &amp; Codex — grill the requirements, optionally cross-review the plan across models, then run it with PM-mode parallel sub-agents.
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

A single model has systematic blind spots — it tends to miss the same edge cases it didn't think to ask about. But simple work shouldn't pay for heavy process either, so starks tiers every task and keeps trivial jobs fast. At the one decision point that matters, handing the plan to *the other* model for a second opinion (Claude↔Codex) catches gaps before any code is written.

## Features

- **Task tiering** — every task is sorted into trivial / light / full before anything runs, so simple work stays fast and only real complexity triggers the full flow.
- **Cross-model review (you choose)** — at sign-off you can send the plan to the *other* engine (Claude↔Codex) for a critical second pass. Never automatic, never silently skipped — it's offered as an option.
- **Work-conserving scheduling** — full tasks use a dependency DAG and Ready queue. Safe Ready work fills each open slot immediately; tightly-coupled work stays sequential instead of being force-split.
- **Truthful status board** — the PM remains responsive, posts live progress in commentary, and accepts `QUERY`, `ADD`, `CHANGE`, `REPLACE`, and `PRIORITY` messages while work continues.
- **Two-stage review** — a reviewer checks spec compliance, then a reviewer checks code quality; failures loop back.
- **Verification gate** — no "done / passing / fixed" claim without freshly-run evidence on the spot.
- **Read opt-in / write opt-in** — Obsidian memory is never read or written automatically. When history may help, starks asks before reading; after reusable progress, it asks separately before writing.
- **Dual-platform** — one `SKILL.md`, symlinked into both Claude Code and Codex.
- **Anti-recursion guard** — when invoked as a cross-reviewer, starks answers once and exits instead of re-entering its own flow.

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
| `STARKS_MEMORY_DIR` | project-memory dir (e.g. an Obsidian vault subfolder); configuration only makes opt-in available | unset |
| `STARKS_STYLE_NOTE` | optional note the memory writer reads first to match your style | unset |

Export sub-agent and memory settings into the primary agent process. Reviewer settings may also live in `.env`; `scripts/cross-review.sh` reads them automatically and already-exported values take precedence.

## How it works

starks doesn't run the same heavyweight pipeline on everything. When real work starts, it first tiers the task:

- **trivial** — a one-line real change, an obvious typo, or a low-risk action with an already-known procedure. Just do it: no grilling, no review, no memory.
- **light** — a single clear concern across a few files. Do it (or confirm in one line) and skip the parallel / cross-review machinery, but the verification gate still applies.
- **full** — multi-file, architectural, large behavior change, or genuinely uncertain. This runs the whole flow.

For a full-tier task the flow is: **ask whether to recall project memory** when history may help (default: skip; after approval, read the short summary first and expand only as needed) → **grill** the requirements — multiple-choice first, batching independent questions — to surface hidden assumptions, edges, and success criteria → **draft** a plan → **present it for one decision** (a hard gate: start now / cross-review first / revise). Only if you pick cross-review does the plan go to the other model; the revised version comes back for sign-off. After approval the PM uses work-conserving scheduling: whenever a slot opens, safe Ready work from the dependency DAG starts without waiting for the whole wave, but work is never force-split merely to raise concurrency. The PM stays responsive, posts a truthful status board in commentary, and accepts new `QUERY`, `ADD`, `CHANGE`, `REPLACE`, and `PRIORITY` messages while work continues. It then runs the **two-stage review**, holds the **verification gate**, and asks separately before writing reusable progress to project memory. Read approval never implies write approval. See the [PM orchestration reference](references/pm-orchestration.md) for the detailed scheduling protocol.

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
