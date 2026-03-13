---
name: pattern-sweep
description: Scans a full client application to generate a summary of active design patterns, deviations from those patterns, and opportunities for cleanup and unification. Covers visual, structural, data-fetching, animation, and interaction patterns. Use when the user says "pattern sweep", "audit patterns", "what patterns are we using", "consistency check", or periodically before a major feature push.
---

# Pattern Sweep

Systematic scan of a codebase to surface what patterns are actually in use — not what was intended, but what exists. The goal: make future development faster and more reliable by knowing exactly what you're working with.

## 1. Identify Pattern Categories

Scan the codebase and organize findings across these dimensions:

- **Data** — Fetching, caching, preloading, optimistic updates, error/loading states
- **Layout** — Page structure, responsive approach, spacing systems, container patterns
- **Components** — Composition patterns, prop conventions, state management boundaries
- **Animation** — CSS transitions vs. motion libraries, timing conventions, use of `will-change` and GPU hints
- **Navigation** — Routing patterns, transition choreography, deep linking
- **Interaction** — Form handling, validation, feedback patterns, touch/click conventions
- **Style** — Theming approach, token usage, inline vs. extracted styles, conditional styling

## 2. Map Each Pattern

For each pattern found, document:

- Where it appears and how frequently
- Whether it's the dominant approach or a one-off
- What it depends on (libraries, utilities, platform APIs)
- How it handles edge cases

## 3. Surface Deviations

Flag anywhere the codebase does the same thing two different ways. For each deviation:

- Which approach came first and which is the evolution
- Whether the deviation is intentional (different context) or accidental (different author/session)
- What unifying on one approach would require

## 4. Recommend Unification

Prioritize opportunities:

1. **High impact** — Deviations that cause bugs or confusion during development
2. **Quick wins** — Inconsistencies fixable with find-and-replace or thin wrappers
3. **Strategic** — Larger consolidations that would pay off across multiple future features

Present findings as a reference document. Do not execute changes — this is reconnaissance.

## Principles

- **Describe what is, not what should be** — accuracy over aspiration.
- **Frequency matters** — a pattern used in 40 places is the pattern; the 3 exceptions are the deviations.
- **No pattern is too small** — inconsistent loading spinners erode trust just like inconsistent data fetching.
- **Context is everything** — a deviation in a legacy module means something different than one in last week's feature.
- **This is a living snapshot** — run it again after major work to keep it current.
