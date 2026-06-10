# starks — Design

## Overview

**starks is a task-launcher skill for AI coding agents.** When you hand the agent
real work — building a feature, adding or changing functionality, refactoring, or
orchestrating a multi-step change — starks decides *how much process the task
deserves*, then runs that much and no more. Trivial work is done directly; only
genuinely complex work walks the full flow of grill → draft → present → sign-off
→ parallel execution → review → verification → memory.

The skill loads on two platforms (Claude Code and Codex CLI) from a single
`SKILL.md`. It is configured entirely through environment variables, has no
runtime dependencies of its own, and degrades gracefully when optional pieces
(cross-model review, memory) are not configured.

The guiding idea is **proportionality**: simple things stay simple, hard things
get the rigor they need, and the user — not the agent — decides when to spend
extra effort.

---

## Task tiers

starks classifies every incoming task into one of three tiers before doing
anything. The tier sets the weight of the process.

| Tier | What it covers | What runs |
|---|---|---|
| **Trivial** | One-line edits, pure lookups, concept explanations, obvious typos, reading a known file, running a known diagnostic. | Done directly. No grilling, no sub-agents. The completion gate still applies. |
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
                              PM: parallel sub-agents
                                            │
                              two-stage review ── fail ─→ (back to execution)
                                            │ pass
                                  verification gate
                                            │ pass
                                       memory (optional)
```

1. **Grill** — Recall project memory first (when a memory dir is configured, read
   the project's summary and memory index so previously-settled questions are not
   re-asked; memory is a snapshot — verify referenced files and conventions still
   hold). Then probe context (read the relevant files and recent history) and
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

4. **User sign-off** — Picking A at step 3 is the sign-off. This is the single
   point past which the agent commits to building.

5. **PM parallel sub-agents** — Acting as a project manager, the agent splits
   independent parts of the work into parallel sub-agents and keeps key decisions
   for itself. (See PM orchestration below.)

6. **Two-stage review** — A reviewer first checks the work against the agreed spec
   (did it build the right thing?), then checks code quality (did it build it
   well?), each following a short prompt template with structured findings.
   Failures send the work back to execution — at most twice; if verification still
   fails after two rework loops, the agent stops and escalates to the user instead
   of looping silently. Independent slices enter review as they finish rather than
   waiting for the slowest one.

7. **Verification gate** — No "done" / "passing" / "fixed" claim is made without
   freshly produced verification evidence (test output, a run, a check). See
   Design principles.

8. **Memory** — If the work made substantial, reusable progress, record a project
   summary. Optional and skipped when not configured. (See Memory layer.)

---

## Cross-model review

This is the signature feature. A single model has *systematic* blind spots — it
tends to miss the same classes of problem in its own plans. starks counters this
by optionally routing the drafted plan to **the other engine** for an adversarial
read: when the primary agent is Claude, the reviewer is Codex, and vice versa.

Key properties:

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

The reviewer may browse the repository read-only to ground its critique, but
never writes or executes changes. A generous timeout (about ten minutes) guards
against hangs. The engine used on the far side is
selected via configuration (see Configuration), defaulting to your strongest
available model.

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

This keeps the recursion exactly one level deep, by construction.

---

## Memory layer

The memory layer is **optional** and exists to make lessons reusable across
projects.

- **Recall at task start.** When configured, the project's summary and memory
  index are read before grilling, so settled decisions and preferences are reused
  instead of re-asked. Project naming is deterministic (repo root basename,
  matched against the existing index) so memory does not fragment across runs.
- **When it runs.** Only after the verification gate passes *and* the work made
  substantial, reusable progress. Trivial changes are skipped so the knowledge
  store does not accumulate noise. The "what happened" log keeps recent dated
  entries instead of being overwritten wholesale; durable user preferences and
  corrections go to the platform's native memory, while the vault keeps the
  narrative summary (pointers, not copies).
- **Where it writes.** A project summary is written under the directory named by
  `STARKS_MEMORY_DIR` — for example, a subdirectory of a personal knowledge vault.
  **If `STARKS_MEMORY_DIR` is unset, the entire memory step is skipped silently.**
- **Cross-project linking.** Summaries link to one another with wikilinks, so a
  related project's notes are one hop away and recurring patterns surface over
  time.
- **Boundaries.** The memory writer reports honestly if it fails (it never claims
  to have written when it did not) and respects any private/excluded paths in the
  target store.

The trigger, boundaries, and "is there real progress?" judgment live in the skill;
the concrete writing style and file conventions live in a memory-writer prompt
template that the writing sub-agent follows.

---

## Cross-platform

starks ships a **single `SKILL.md`** that loads on both Claude Code and Codex CLI.
Portability is achieved by writing the contract in **action-neutral language**
("spawn parallel sub-agents", "ask the user a single multiple-choice question",
"track progress") and providing a tool-mapping table so each platform binds the
neutral action to its native tool.

| Action | Claude | Codex |
|---|---|---|
| Spawn parallel sub-agents | `Task` | `spawn_agent` |
| Await / release a sub-agent | returns automatically | `wait_agent` / `close_agent` |
| Ask the user a question | `AskUserQuestion` | terminal follow-up prompt |
| Track progress | `TodoWrite` | `update_plan` |
| Invoke the other engine (cross-review) | the Codex CLI | the Claude CLI |

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

- **Parallelize when you can; don't force splits.** The PM splits genuinely
  independent work into parallel sub-agents for speed. When dependencies are
  strong and the work does not decompose cleanly, the agent does it sequentially
  and records why — forcing an artificial split only adds coordination cost.
  Sub-agent prompts are focused, self-contained, state their outputs and
  acceptance criteria explicitly, and declare the files each agent owns: parallel
  agents' write-sets must be disjoint, otherwise the work is sequenced or isolated
  in worktrees.

- **Configuration via environment variables.** All tunables — which model
  sub-agents use, which model reviews on the far side, where memory is written,
  the cross-review recursion guard — are environment variables with sensible
  defaults or graceful skips. There is no config file to maintain and no required
  setup; an unset variable means "use the default" or "skip this feature", never
  "fail".

Defaults favor your strongest available model for sub-agents, review, and the
memory writer, since the full tier is reserved for work where quality matters more
than cost. The lighter tiers stay deliberately cheap.
