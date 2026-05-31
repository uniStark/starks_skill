<h1 align="center">starks</h1>

<p align="center">
  A task-launcher skill for Claude Code &amp; Codex — grill the requirements, optionally cross-review the plan across models, then run it with PM-mode parallel sub-agents.
</p>

<p align="center">
  English | <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/Claude%20Code-skill-8A2BE2" alt="Claude Code">
  <img src="https://img.shields.io/badge/Codex-skill-10A37F" alt="Codex">
</p>

## Why starks?

A single model has systematic blind spots — it tends to miss the same edge cases it didn't think to ask about. But simple work shouldn't pay for heavy process either, so starks tiers every task and keeps trivial jobs fast. At the one decision point that matters, handing the plan to *the other* model for a second opinion (Claude↔Codex) catches gaps before any code is written.

## Features

- **Task tiering** — every task is sorted into trivial / light / full before anything runs, so simple work stays fast and only real complexity triggers the full flow.
- **Cross-model review (you choose)** — at sign-off you can send the plan to the *other* engine (Claude↔Codex) for a critical second pass. Never automatic, never silently skipped — it's offered as an option.
- **PM-mode parallel sub-agents** — independent slices fan out to parallel sub-agents; tightly-coupled work stays sequential instead of being force-split.
- **Two-stage review** — a reviewer checks spec compliance, then a reviewer checks code quality; failures loop back.
- **Verification gate** — no "done / passing / fixed" claim without freshly-run evidence on the spot.
- **Optional memory layer** — a project summary can be written to a knowledge base (e.g. Obsidian) when there's reusable progress; skipped entirely if unconfigured.
- **Dual-platform** — one `SKILL.md`, symlinked into both Claude Code and Codex.
- **Anti-recursion guard** — when invoked as a cross-reviewer, starks answers once and exits instead of re-entering its own flow.

## Requirements

- Claude Code **or** Codex CLI
- `bash`
- macOS or Linux
- Cross-model review needs the *other* engine's CLI on your `PATH` (`claude` / `codex`)
- Optional: a knowledge base such as Obsidian for the memory step; `gh` (maintenance only)

## Installation

```bash
bash scripts/install.sh
```

This symlinks the repo into `~/.claude/skills/starks` and `~/.codex/skills/starks`, so both engines share the same `SKILL.md`. Existing files or symlinks pointing elsewhere are left untouched.

## Configuration

starks reads a few optional environment variables (all have defaults or degrade gracefully):

| Env var | What | Default |
|---|---|---|
| `STARKS_AGENT_MODEL` | strongest model for parallel sub-agents | your platform's strongest (e.g. Claude `opus`, Codex `gpt-5`-class) |
| `STARKS_REVIEW_MODEL` | model used for cross-review on the OTHER engine | same |
| `STARKS_MEMORY_DIR` | project-memory dir (e.g. an Obsidian vault subfolder); **unset → memory step skipped** | unset |
| `STARKS_STYLE_NOTE` | optional note the memory writer reads first to match your style | unset |

Copy `.env.example` and adjust the values for your setup.

## How it works

starks doesn't run the same heavyweight pipeline on everything. When real work starts, it first tiers the task:

- **trivial** — a one-line edit, a lookup, a concept explanation, an obvious typo. Just do it: no grilling, no review, no memory.
- **light** — a single clear concern across a few files. Do it (or confirm in one line) and skip the parallel / cross-review machinery, but the verification gate still applies.
- **full** — multi-file, architectural, large behavior change, or genuinely uncertain. This runs the whole flow.

For a full-tier task the flow is: **grill** the requirements one question at a time to surface hidden assumptions, edges, and success criteria → **draft** a plan → **present it for one decision** (a hard gate: start now / cross-review first / revise). Only if you pick cross-review does the plan go to the other model; the revised version comes back for sign-off. After approval the PM **fans out parallel sub-agents** for the independent work, runs the **two-stage review**, holds the **verification gate**, and — when a memory dir is configured and there's reusable progress — records a **project summary** to your knowledge base.

## Cross-platform

One skill, two engines — starks maps each step to the platform's native tools.

| Action | Claude | Codex |
|---|---|---|
| Spawn parallel sub-agents | `Task` / `Agent` | `spawn_agent` |
| Track progress | `TodoWrite` | `update_plan` |
| Cross-model review | `codex exec -m "$STARKS_REVIEW_MODEL" …` | `claude -p --model "$STARKS_REVIEW_MODEL" …` |

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
