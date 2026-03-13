---
name: debug
description: Structured investigation when something is broken. Follows a disciplined trace from symptoms to root cause, resisting the urge to guess or patch over symptoms. Use when the user says "debug", "investigate", "this is broken", "why is this happening", "something's wrong", or when encountering unexpected behavior during a build.
---

# Debug

Something isn't working. Before touching any code, understand why. The goal: find the root cause, not the nearest fix that makes the symptom disappear.

## 1. Establish the Symptom

State precisely what's happening:

- What is the expected behavior?
- What is the actual behavior?
- When did it start (or was it always this way)?
- Is it consistent or intermittent?

Do not skip this step. Vague symptoms lead to vague fixes.

## 2. Reproduce

Find the shortest path to trigger the issue:

- What inputs, state, or sequence produces it?
- Does it reproduce in all environments or only some?
- What's the minimum case — can anything be stripped away while still reproducing?

If it can't be reproduced, the next step is adding instrumentation, not guessing.

## 3. Trace the Code Path

Follow the actual execution path from trigger to symptom:

- Read the code that runs, in order. Don't skip files or assume you know what they do.
- Check the data at each boundary — what goes in and what comes out?
- Identify where reality diverges from expectation. That's the neighborhood of the bug.

## 4. Form and Test a Hypothesis

Based on the trace:

- State what you believe the cause is and why
- Predict what a fix would change — not just the symptom, but the data flow
- Verify the hypothesis before implementing — add a log, check a value, confirm the assumption

If the hypothesis is wrong, return to step 3 with new information. Do not iterate on fixes.

## 5. Fix and Verify

Implement the smallest change that addresses the root cause:

- Does the original reproduction case pass?
- Do related cases still work? (Regressions from fixes are common)
- Is the fix consistent with the codebase's patterns, or is it a workaround that needs a comment?

If the fix feels like a workaround, say so. A known workaround is better than a disguised one.

## Principles

- **Read before you guess** — most bugs are obvious once you look at the right code.
- **Symptoms lie** — the visible problem is rarely where the actual problem lives.
- **One cause, one fix** — if the fix touches many places, you might be treating symptoms.
- **Resist the patch** — a quick fix that doesn't address root cause creates the next bug.
- **Name what you don't know** — uncertainty is information; hiding it wastes time.
