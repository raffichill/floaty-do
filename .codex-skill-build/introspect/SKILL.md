---
name: introspect
description: Post-feature reflection on the decisions and patterns chosen during a build. Synthesizes what was learned with the goal of accumulating knowledge and feeding insights back into living documents like design-principles. Use when the user says "introspect", "reflect on this", "what did we learn", "wrap up", or when moving on from a completed feature or release.
---

# Introspect

Pause after shipping to extract what the build actually taught. This is not a retro about process — it's about the technical and design decisions that were made, whether they held up, and what should be carried forward.

## 1. Inventory the Decisions

Walk through the feature as built. For each significant decision, document:

- **What was chosen** — Framework, pattern, component, architecture approach
- **What was considered** — Alternatives that were evaluated or attempted
- **Why this won** — The specific reason this approach was selected (performance, simplicity, consistency, time)
- **How it held up** — Did the decision stay clean through implementation, or did it require workarounds?

Include decisions at every level: architecture, data model, component structure, animation approach, API design.

## 2. Identify New Knowledge

Extract insights that didn't exist before this build:

- **Confirmed patterns** — Approaches that proved reliable and should be reused
- **Broken assumptions** — Things expected to work that didn't, and why
- **Platform discoveries** — Capabilities, limitations, or behaviors learned about the platform
- **Cost surprises** — Things that were harder or easier than expected

## 3. Recommend Updates

Based on what was learned, propose specific additions or amendments to:

- **design-principles** — New principles that crystallized, or platform-specific notes to add under existing ones
- **CLAUDE.md / project docs** — Conventions or gotchas worth codifying for future sessions
- **Existing code** — Patterns in older features that should be updated to match what was learned

Present each recommendation with the evidence from this build. Do not update documents without approval.

## 4. Close the Loop

Summarize in a few sentences:

- What this feature taught that applies beyond itself
- What to watch for in the next build
- Anything intentionally left imperfect and why

## Principles

- **Decisions are data** — every choice reveals something about the problem space.
- **Hindsight is the point** — knowing you'd choose differently now is a win, not a failure.
- **Accumulate, don't repeat** — if it was learned once, write it down so it's never relearned.
- **Living documents earn their name** — principles that never update aren't principles, they're artifacts.
