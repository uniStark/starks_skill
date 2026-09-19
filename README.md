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
- **Cross-model review (you choose)** — for design docs and major changes, the plan gate offers **start now / cross-review / revise**; everything else defaults to no review, and you can request one anytime. On pi the reviewer is a one-shot sub-agent whose model and thinking depth you pick from pi's registry; on Claude/Codex it is the other engine's CLI. Review is never automatic and never silently skipped.
- **Work-conserving scheduling** — a dependency DAG and Ready queue fill open slots as soon as safe work appears. Strongly coupled slices stay sequential instead of being split for vanity parallelism.
- **Lean sub-agents** — the PM sends each flat child a compact **“派活单 + 随身小抄”** (work order + context cheat sheet). Children do not reload the session, general project docs, or recent commits; they return one bounded **“收工小票”** (completion receipt).
- **Truthful status board** — the PM stays responsive, shows real state rather than invented percentages or ETAs, and keeps accepting `QUERY`, `ADD`, `CHANGE`, `REPLACE`, and `PRIORITY` while execution continues.
- **Two-stage review** — spec compliance comes first, code quality second. Failed slices go back for bounded rework instead of disappearing into a vague “done.”
- **Verification gate** — no “done / passing / fixed” claim without freshly-run evidence that matches the acceptance criteria.
- **Self-contained specialist paths** — bugs start with reproduction and root-cause evidence, skill edits verify the real installed entrypoint, and uncertain designs use the full plan gate. No external workflow-skill plugin is required.
- **Dual-platform, recursion-safe** — one `SKILL.md` serves Claude Code and Codex. A cross-reviewer answers once and exits instead of invoking starks again.

## The signature PM loop

```text
request
  └─ task tier → requirement grill → plan
                                  └─ you choose: start / revise
                                       (+ cross-review option for designs
                                        and major changes — never automatic)
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

- Claude Code, Codex CLI, **or** pi
- `bash`
- `python3` (process-group timeout runner)
- macOS or Linux
- Cross-model review: on Claude/Codex it needs the *other* engine's CLI on your `PATH` (`claude` / `codex`); on pi it needs the `subagent` tool, or an external CLI as fallback
- Optional: `gh` (maintenance only)

## Installation

The same package can be used by pi. pi discovers skills from `~/.agents/skills/`, so the default installer works for pi and Codex together. For a pi-only explicit load, use `pi --skill /path/to/starks_skill` or install the repository link first and invoke `/skill:starks`.

```bash
bash scripts/install.sh
```

This symlinks the repo into `~/.claude/skills/starks` and Codex's active skill root. Codex uses `$CODEX_HOME/skills/starks` when `CODEX_HOME` is set; otherwise it uses the cross-client location `~/.agents/skills/starks`. Existing files or symlinks pointing elsewhere are left untouched, and any failed verification makes the installer exit non-zero. Inactive links in the recognized Codex locations are removed only when they point to this repo and every new entrypoint has verified successfully.

## Configuration

starks reads a few optional environment variables (all have defaults or degrade gracefully):

| Env var | What | Default |
|---|---|---|
| `STARKS_REVIEW_MODEL_CODEX` | reviewer model when Codex reviews the plan (Claude→Codex) | unset → codex default |
| `STARKS_REVIEW_MODEL_CLAUDE` | reviewer model when Claude reviews the plan (Codex→Claude) | unset → claude default |
| `STARKS_REVIEW_TIMEOUT_SECONDS` | cross-review timeout in seconds | `600` |
| `STARKS_REVIEW_MODEL_PI` | pi reviewer model (exact `provider/id` from pi's registry) | unset/empty → ask during review setup |
| `STARKS_REVIEW_THINKING_PI` | pi reviewer thinking depth | unset/empty → ask (`high` suggested) |
| `STARKS_AGENT_MODEL_PI` | default model for pi PM-dispatched sub-agents | unset/empty → platform default |
| `STARKS_AGENT_THINKING_PI` | default thinking depth for pi sub-agents | unset/empty → platform default |

Sub-agents inherit the platform's global model and thinking-depth defaults. The PM may choose supported overrides based on task complexity, risk, and cost, while respecting explicit user settings and platform rules. On pi you can also save your own default sub-agent model and thinking depth (chosen from pi's registry via `/skill:starks subagents`, or the one-time offer at the full-tier plan gate); a saved default binds every dispatch and the PM may only suggest deviations. Choices never rewrite global settings; unsupported or unverified selections must be reported honestly. See [runtime rules](references/runtime.md).

The first three variables apply only to the external cross-review wrapper, the two `STARKS_REVIEW_*_PI` keys only to pi's review sub-agent, and the `STARKS_AGENT_*_PI` keys only to pi's PM-dispatched sub-agents. Reviewer settings may also live in `.env`; `scripts/cross-review.sh` reads them automatically and already-exported values take precedence. The pi keys are written to `.env` when you approve "save as default" in the setup flows; manage them anytime via the `/skill:starks cross-review` and `/skill:starks subagents` settings consoles (any other skill arguments are treated as the task).

## How it works

starks doesn't run the same heavyweight pipeline on everything. When real work starts, it first tiers the task:

- **trivial** — a one-line real change, an obvious typo, or a low-risk action with an already-known procedure. Just do it: no grilling or cross-review.
- **light** — a single clear concern across a few files. Do it (or confirm in one line) and skip the parallel / cross-review machinery, but the verification gate still applies.
- **full** — multi-file, architectural, large behavior change, or genuinely uncertain. This runs the whole flow.

For a full-tier task the flow is: **grill** the requirements → **draft** a plan → **present it for one decision** (start / revise, plus a cross-review option for design docs and major changes). Only after sign-off does the PM execute, using platform-supported delegation or a sequential fallback, then run the **two-stage review** and **verification gate**. See the [PM orchestration reference](references/pm-orchestration.md) and [runtime reference](references/runtime.md).

Cross-review uses one stable wrapper; the full plan always travels over stdin:

```bash
scripts/cross-review.sh codex /path/to/repo < plan.md   # Claude → Codex
scripts/cross-review.sh claude /path/to/repo < plan.md  # Codex → Claude
```

## pi usage

starks probes pi's actual tools each session. With the `subagent` tool (pi-subagents) it runs the full PM orchestration, and cross-review runs as a one-shot reviewer sub-agent whose model and thinking depth you pick — optionally saved as defaults in `.env`. Without that tool it falls back to sequential execution: present the plan, wait for approval, execute one slice at a time, perform the two review stages, and run the final verification. Use `.starks/plan.md` and `.starks/board.md` only for full tasks where durable progress is useful.

```bash
bash scripts/install.sh
pi
# then: /skill:starks
```

The installer does not change pi authentication, models, settings, or extensions. Sub-agents inherit the platform global model and thinking-depth defaults; the PM may choose supported per-dispatch overrides when justified.

## Cross-platform

One skill, two engines — starks maps each step to the platform's native tools.

| Action | Claude | Codex | pi |
|---|---|---|---|
| Spawn parallel sub-agents | `Task` / `Agent` | `spawn_agent` when available | `subagent` when available, else sequential |
| Track progress | `TodoWrite` | `update_plan` | `todo` when available, else `.starks/board.md` |
| Cross-model review | `scripts/cross-review.sh codex …` | `scripts/cross-review.sh claude …` | `subagent` reviewer (wrapper only for external CLIs) |
| Select sub-agent model | platform default or PM decision | platform default or PM decision | platform default or PM decision (`provider/id:thinking`) |

## Uninstall

```bash
bash scripts/uninstall.sh
```

Removes only recognized Claude/Codex symlinks, including the legacy Codex location, and only when they actually point at this repo (symlinks pointing elsewhere, or non-symlinks, are skipped). The source repo is never touched. Preview without removing:

```bash
DRY_RUN=1 bash scripts/uninstall.sh
```

## License

MIT

---

See [`docs/DESIGN.md`](docs/DESIGN.md) for the design rationale.
