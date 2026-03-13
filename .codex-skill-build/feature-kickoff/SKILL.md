---
name: feature-kickoff
description: Pre-build preparation for a new feature. Scans the codebase for related features and endpoints, then asks clarifying questions to ensure cohesiveness with the existing product before any code is written. Use when the user says "feature kickoff", "new feature", "let's build", "starting on [feature]", or at the beginning of any significant new work.
---

# Feature Kickoff

Preparation before writing a single line. The goal: understand what already exists so the new feature feels like it was always part of the product.

## 1. Scan for Related Work

Search the codebase for anything adjacent to the new feature:

- **Existing features** — What already does something similar or overlapping? How does it work?
- **Endpoints and data** — What API routes, data models, and queries touch the same domain? What's the shape of the data?
- **Components** — What UI building blocks already exist that this feature should reuse?
- **Patterns** — How do similar features handle loading, errors, navigation, and state? What's the established approach?

Surface the full picture, including anything that might need to change to accommodate the new feature.

## 2. Ask Clarifying Questions

Based on what was found, ask targeted questions before building:

- **Scope** — What's in v1 and what's deferred? Where are the boundaries?
- **Interaction model** — How does the user get here, and where do they go next?
- **Edge cases** — What happens when data is empty, loading fails, or permissions are missing?
- **Consistency** — Are there existing patterns this feature should follow, or is this an opportunity to establish a new one?
- **Dependencies** — Does this require backend changes, new data, or coordination with other features?

Only ask questions that the codebase scan didn't already answer.

## 3. Propose an Approach

Before writing code, outline:

- What files will be created or modified
- Which existing components and patterns will be reused
- Where the new feature fits in the navigation and data flow
- Any patterns that need to be established (and why)

Wait for alignment before proceeding.

## Principles

- **The codebase is the spec** — what exists tells you more than what was planned.
- **Reuse is the default** — build new only when existing patterns genuinely don't fit.
- **Ask early, not mid-build** — confusion at the start costs minutes; confusion mid-build costs hours.
- **Cohesion over speed** — a feature that fits the product is worth more than a feature that ships fast.
