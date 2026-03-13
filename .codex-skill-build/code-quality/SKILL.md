---
name: code-quality
description: Post-implementation retrospective and refactoring pass. Reviews conversation history to synthesize what was learned during iteration, then refactors the final code for elegance, repo consistency, and future extensibility. Use when the user says "code quality", "refactor pass", "clean up what we built", "polish this", or after any substantial build.
---

# Code Quality Retrospective

Final quality pass after substantial implementation work. The core question: **knowing what you know now, how would you refactor this?**

## 1. Mine the Conversation

Review the full conversation history. Extract:

- What was built
- How the approach evolved
- Dead ends and why they failed
- Patterns that crystallized mid-build

Identify the **knowledge delta** — everything known now that wasn't known at the start.

## 2. Audit Every Touched File

Re-read all created or modified files. Evaluate each against:

- **Structure** — Single responsibility? Right abstraction level? Understandable without conversation context?
- **Repo consistency** — Follows existing patterns, naming, conventions? Existing utilities that could replace custom code? Leftovers?
- **Extensibility** — Anything hardcoded that should be configurable?

## 3. Present Refactor Plan

Organize by priority:

1. **Critical** — Bugs, wrong abstractions, broken consistency
2. **Structural** — Extract, consolidate, align with repo patterns
3. **Polish** — Naming, simplification, tighter types

For each item: what it is, how it ended up that way, and what it should become.

Wait for user approval before executing.

## 4. Execute and Summarize

Implement in reviewable chunks with verification after each. Surface deeper issues rather than silently working around them.

Finish with:

- What changed
- How it positions the repo for future work
- Anything intentionally deferred

## Principles

- **Respect the iteration** — the conversation is context, not mistakes.
- **The repo is the unit** — every change makes the wider codebase more coherent.
- **Elegance is clarity** — communicate intent, don't impress.
- **Delete more than you add** — fewer moving parts for the same behavior.
- **Existing patterns win** — consistency compounds.
