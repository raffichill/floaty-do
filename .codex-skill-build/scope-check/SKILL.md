---
name: scope-check
description: Mid-build checkpoint that compares current work against original intent. Flags scope creep, identifies what should be deferred, and re-centers on the core goal. Use when the user says "scope check", "are we overbuilding", "gut check", "is this too much", or when a feature branch is growing beyond its original intent.
---

# Scope Check

Pause mid-build. Compare what's happening to what was supposed to happen. The goal: catch drift early before it compounds.

## 1. Restate the Original Intent

From the feature kickoff, initial conversation, or commit history — what was the actual goal? State it in one or two sentences. If the goal was never clearly stated, that's the first finding.

## 2. Map Current Work Against Intent

Review everything that's been built or changed so far:

- **On target** — Directly serves the stated goal
- **Supporting** — Doesn't serve the goal directly but is necessary to make it work (infrastructure, refactors, fixes)
- **Adjacent** — Related but not required for the stated goal
- **Unrelated** — How did this get in here?

## 3. Evaluate the Adjacent Work

For anything marked adjacent, ask:

- Does it need to ship with this feature, or can it be a follow-up?
- Is it making the current PR harder to review or test?
- Was it discovered mid-build (legitimate expansion) or is it gold-plating?

## 4. Recommend a Path

Present one of:

- **Stay the course** — Current scope is justified, keep going
- **Trim** — Specific items to extract into follow-up work, with reasoning
- **Refocus** — The build has drifted significantly; here's what to finish now and what to shelve

Be direct. The point is to save time, not add process.

## Principles

- **Scope creep is invisible from inside** — the whole point is an outside perspective.
- **Adjacent work is the trap** — it always feels justified in the moment.
- **Smaller PRs compound** — two focused changes are better than one sprawling one.
- **Deferring is not dropping** — capturing follow-up work explicitly means it doesn't get lost.
