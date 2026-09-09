# starks — Design

## Overview

**starks is a task-launcher skill for AI coding agents.** When you hand the agent
real work — building a feature, adding or changing functionality, refactoring, or
orchestrating a multi-step change — starks decides *how much process the task
deserves*, then runs that much and no more. Trivial work is done directly; only
genuinely complex work walks the full flow of grill → draft → present → sign-off
→ parallel or sequential execution → review → verification.

The skill loads from a single `SKILL.md` on Claude Code, Codex CLI, and pi.
External cross-review is configured through environment variables and requires
Bash, Python 3, and the reviewer CLI. Sub-agent model and thinking depth inherit
platform defaults or are chosen per task by the PM. pi uses a sequential fallback
because it has no built-in sub-agent or plan system.

The guiding idea is **proportionality**: simple things stay simple, hard things
get the rigor they need, and the user — not the agent — decides when to spend
extra effort.

---

## Task tiers

starks classifies every incoming task into one of three tiers before doing
anything. The tier sets the weight of the process.

| Tier | What it covers | What runs |
|---|---|---|
| **Trivial** | One-line real changes, obvious typos, or low-risk actions with an already-known procedure. | Done directly. No grilling, no sub-agents. The completion gate still applies. |
| **Lightweight** | Small, self-contained changes with low uncertainty and a clear single owner. | Brief clarification if useful, then direct execution. Low overhead — do not reach for sub-agents reflexively. |
| **Full** | Anything spanning multiple files or modules, architectural change, significant behavior change, high uncertainty, or work that needs design before implementation. | The complete full-tier flow described below. |

**Why tier at all?** A single heavyweight pipeline applied to every request wastes
time and erodes trust on small asks; a single lightweight path applied to every
request misses requirements and ships under-reviewed work on big ones. Tiering
keeps simple things simple while reserving cross-review, parallel orchestration,
and the verification gate for tasks that actually warrant them.

When uncertain between two tiers, round **up** — it is cheaper to ask one extra
question than to under-scope a real change.

---

## The full-tier flow

The full tier is a small state machine. Each stage feeds the next; one stage is a
hard gate (see Design principles).

```
grill → draft → present + decide ─┬─ (A) proceed ─────────────┐
                                  ├─ (B) cross-review → revise ┘ (back to present)
                                  └─ (C) revise the plan ───── (back to grill/draft)
                                            │
                              user sign-off (the "present + decide" gate)
                                            │
                    PM: Ready queue → 派活单 → flat sub-agents
                                      ↓
                                  收工小票
                                            │
                              two-stage review ── fail ─→ (back to execution)
                                            │ pass
                                  verification gate
```

1. **Grill** — Probe the current repository (read relevant files and necessary history) and
   interrogate requirements with multiple-choice prompts, batching independent
   questions and sequencing only those whose answers gate later ones. Surface
   hidden assumptions, edge cases, and success criteria. This is conversational,
   not a form.

2. **Draft** — Close the requirements into a concrete plan and a task breakdown.
   The draft is lightweight and lives in the conversation; it is not a separate
   plan artifact.

3. **Present + decide** *(HARD-GATE)* — Show the plan to the user and offer exactly
   three choices:
   - **A — Proceed.** Move straight to execution.
   - **B — Cross-review first.** Have the *other* engine review the plan, fold the
     feedback into a revised plan, and return to this step.
   - **C — Revise.** Adjust the plan and re-present.

   Execution never starts until the user picks A. Cross-review never runs unless
   the user picks B.

4. **PM orchestration** — Picking A at step 3 is the sign-off. The PM maintains a
   dependency DAG and continuously fills open slots from the Ready queue. It sends
   each child a compact “派活单 + 随身小抄”, keeps the agent tree one level deep,
   and accepts only a bounded “收工小票”. Children do not reread the session,
   general project docs or commit history; they read named target files,
   necessary direct dependencies, and mandatory scoped project rules only.

5. **Two-stage review** — A reviewer first checks the work against the agreed spec
   (did it build the right thing?), then checks code quality (did it build it
   well?), each following a short prompt template with structured findings.
   Failures send the work back to execution — at most twice; if verification still
   fails after two rework loops, the agent stops and escalates to the user instead
   of looping silently. Independent slices enter review as they finish rather than
   waiting for the slowest one.

6. **Verification gate** — No "done" / "passing" / "fixed" claim is made without
   freshly produced verification evidence (test output, a run, a check). See
   Design principles.

---

## Cross-model review

This is the signature feature. A single model has *systematic* blind spots — it
tends to miss the same classes of problem in its own plans. starks counters this
by optionally routing the drafted plan to **the other engine** for an adversarial
read: when the primary agent is Claude, the reviewer is Codex, and vice versa.

Key properties:

- **The plan travels via stdin, not as a command-line argument.**
  `scripts/cross-review.sh` combines the fixed review prompt and the full plan
  into one delimited stdin request. Codex receives `-` explicitly so it cannot
  interpret the positional review prompt while silently omitting piped plan data.
  Passing a large plan as an argument risks hitting the OS `ARG_MAX` limit —
  which either errors out or, worse, silently truncates so the reviewer sees
  only part of the plan. stdin has no such limit.
- **User-triggered, never automatic.** Cross-review is option **B** at the
  present-and-decide gate. The agent neither runs it silently nor quietly skips it
  — it always offers it as a choice and lets the user decide.
- **Single round, synchronous.** The full plan plus a review prompt are sent to
  the other engine; the agent waits for the critique, folds it into a revised
  plan, and returns to the present-and-decide gate for a fresh A/B/C decision.
- **The reviewer only reviews.** It supplements and corrects the plan and then
  stops — it does not start building.
- **Failures are surfaced, not swallowed.** If the other engine errors, is
  unavailable, or times out, the agent reports honestly that review did not
  complete and offers the user a choice (retry / switch reviewer / explicitly
  skip this round). It never pretends review passed.

Codex runs in a disposable empty workspace with its shell, sub-agent, app, web,
and image tools disabled; its child-process environment inheritance is also set
to none as defense in depth. Claude runs with tools disabled. Both review only
the supplied plan and receive no repository context. Neither reviewer reads,
writes, or executes project content. A generous timeout (about ten minutes)
guards against hangs. The engine used on the far side is selected via
configuration (see Configuration), defaulting to the reviewer CLI's configured
model.

---

## Anti-recursion guard

Cross-review invokes one engine from inside the other. Without a guard, the
reviewer engine would itself load starks, draft a plan, and try to cross-review
*back* — an infinite ping-pong.

The guard is a single environment variable, `STARKS_CROSS_REVIEW=1`, set on the
invocation when the agent calls the other engine as a reviewer. This is the
**first thing** starks checks on startup:

- If `STARKS_CROSS_REVIEW` is set, the agent knows it is being invoked purely as a
  one-shot plan reviewer. It does **not** enter the starks flow, does not load any
  skill, does not spawn sub-agents, and does not call back into the other engine.
  It simply critiques the plan it received and exits.
- If the variable is unset, it is the primary agent and proceeds normally.

The wrapper also refuses to start when that variable is already present. This
turns a prompt-level recursion rule into a second, deterministic process-level
guard.

This keeps the recursion exactly one level deep, by construction.

When Claude invokes Codex as the reviewer, the guard is doubled structurally:
the wrapper also disables the starks skill via Codex's path-based per-skill
`skills.config` override. It supplies both the skill-directory and `SKILL.md`
file forms because supported Codex releases have interpreted this path
differently. The reviewer receives a read-only sandbox inside a disposable empty
workspace, with active tool surfaces disabled, and treats the plan as untrusted
review data. It ignores user configuration and execpolicy rules and runs
ephemerally, so unrelated plugins, hooks and stale configuration cannot affect
the review. The wrapper deliberately does not enable `--strict-config` because
user configuration is not loaded in the first place.

The Claude direction uses safe mode, disables slash commands and tools, and
disables session persistence. This isolates the reviewer from user/project
hooks, plugins, skills and resumable sessions while preserving normal auth.

---

## Cross-platform

starks ships a **single `SKILL.md`** that loads on Claude Code, Codex CLI, and pi.
Portability is achieved by writing the contract in **action-neutral language**
("spawn parallel sub-agents", "ask the user a single multiple-choice question",
"track progress") and providing a tool-mapping table so each platform binds the
neutral action to its native tool.

| Action | Claude | Codex | pi |
|---|---|---|---|
| Spawn parallel sub-agents | `Task` | `spawn_agent` when available | sequential fallback |
| Await / release a sub-agent | returns automatically | `wait_agent` / platform mechanism | not applicable by default |
| Ask the user a question | `AskUserQuestion` | `request_user_input` when available | direct follow-up |
| Track progress | `TodoWrite` | `update_plan` | optional `.starks/board.md` |
| Invoke the other engine (cross-review) | Codex CLI | Claude CLI | external Codex / Claude CLI |

The skill body never hard-codes a platform's tool name in its prose; it refers to
the neutral action and lets the table resolve it. This keeps a single source of
truth and avoids drift between two platform-specific copies.

---

## Design principles

- **HARD-GATE on present-and-decide (full tier only).** Execution must not begin
  before the user signs off on a presented plan. This gate exists only in the full
  tier — trivial and lightweight work has nothing to gate. The gate is also where
  cross-review is offered, so the user controls both *whether to build* and
  *whether to get a second opinion first*.

- **The completion gate is universal.** Every tier — including trivial — must
  produce verification evidence before claiming success. "Should work" is not
  evidence; a run, a passing test, or an observed result is. This is the one rule
  that never relaxes with tier.

- **Keep safe slots busy; don't force splits.** The PM continuously recomputes the
  Ready/review queues and fills an open slot immediately instead of waiting for a
  wave. Strong dependencies or overlapping write sets stay sequential unless a
  real worktree isolates them. Every child receives a focused work order, minimal
  context, capability boundary, write ownership, acceptance criteria, and return
  budget. Only the PM spawns agents; children never spawn grandchildren.

- **Cross-review configuration via environment variables.** Reviewer models,
  timeout and the recursion guard use environment variables. The wrapper also
  reads reviewer settings from `.env`; exported values take precedence. These
  settings do not select models for PM-dispatched sub-agents.

When a sub-agent tool cannot select a model or thinking depth, starks inherits platform
configuration and does not claim that an override was enforced. The lighter tiers
stay deliberately cheap.

Sub-agent model and thinking depth are not hard-coded. Prefer the platform global
configuration; the PM may choose supported overrides based on complexity, risk,
and cost, respecting explicit user settings and platform rules. Choices apply
only to the dispatch and never rewrite global configuration. Check support for
model and thinking-depth selection independently, and distinguish a requested
setting from one verified by runtime metadata.
