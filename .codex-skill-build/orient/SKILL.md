---
name: orient
description: Session opener that scans a codebase to build a working mental model of the project. Produces a snapshot of the stack, structure, active patterns, recent changes, and open work. Use when the user says "orient", "catch me up", "where were we", "what's the state of this", or at the start of a session in an unfamiliar or dormant project.
---

# Orient

Get bearings before doing anything. The goal: a working mental model of the project in its current state — not documentation-level detail, just enough to make good decisions.

## 1. Project Snapshot

Scan and summarize:

- **Stack** — Languages, frameworks, key dependencies, build system
- **Structure** — How the codebase is organized (directories, modules, entry points)
- **Scale** — Rough size in files and lines; how many distinct features or screens

## 2. Active Patterns

Identify the dominant patterns in use, not exhaustively (that's pattern-sweep) but enough to avoid introducing inconsistencies:

- State management approach
- Data fetching and caching
- Component composition style
- Routing and navigation
- Styling approach

## 3. Recent Activity

Check recent history for context:

- Last few commits — what was being worked on?
- Open branches — anything in progress?
- Modified but uncommitted files — anything left mid-task?
- Open issues or PRs — what's pending?

## 4. Surface Anything Unusual

Flag anything that looks unexpected or worth noting:

- Configuration that deviates from defaults
- Dependencies that are outdated or unusual
- Dead code, disabled features, or TODO markers
- Anything that would trip up someone starting fresh

Present the full picture in a concise summary. This is reconnaissance — no changes, no recommendations, just a clear snapshot.

## Principles

- **Speed over depth** — good enough in 2 minutes beats thorough in 20.
- **Current state, not history** — what matters is what's here now, not how it got here.
- **Flag, don't fix** — note problems but don't solve them; that's a separate decision.
- **Every session benefits** — even in a familiar project, a quick orient catches things that changed since last time.
