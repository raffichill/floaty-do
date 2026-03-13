---
name: design-principles
description: Living reference document defining the design philosophy that underpins every product. Covers both visual design and the engineering decisions that shape how software feels. Updated via introspect after significant builds. Use when the user says "design principles", "what are our principles", "how should this feel", or when evaluating a design/architecture decision against project values.
---

# Design Principles

These principles govern how we build — not just how things look, but how they behave, perform, and feel. They apply to every layer: UI, interaction, data, architecture. Each principle is universal; platform-specific notes clarify how it manifests in context.

---

## Native

Use the most performant and robust primitives available for the platform. Reach for what the system provides before introducing abstractions. Native doesn't mean "no libraries" — it means the foundation is the platform itself, and everything else earns its place.

### On iOS
- UIKit where performance and control matter. SwiftUI where declarative composition is the win.
- System components (UINavigationController, UIScrollView) over custom replacements unless the UX demands it.
- Respect platform conventions — gestures, safe areas, dynamic type.

### On Web
- Platform APIs (Intersection Observer, View Transitions, native form validation) over library equivalents.
- Semantic HTML as the structural foundation.
- CSS for layout and most animation; JS libraries only when CSS genuinely can't express the behavior.

---

## Effective

Help the user achieve their goal with no extra fluff or friction. Every element on screen should either advance the user's task or get out of the way. Features are not a list of capabilities — they're paths to outcomes.

- Reduce steps to completion. If something can be inferred, don't ask.
- Default to the right thing. Settings are an escape hatch, not a feature.
- Empty states, loading states, and error states are part of the experience, not afterthoughts.

---

## Consistent

A UI should feel intentional at every level. Same action, same result, everywhere. Consistency isn't about rigidity — it's about building trust through predictability.

- Components behave identically in every context they appear.
- Spacing, typography, and color follow a system, not ad-hoc values.
- Naming in code reflects naming in UI reflects naming in conversation.
- When a pattern exists, use it. When a pattern is wrong, change it everywhere.

---

## Choreographed

The timing of interactions reflects the stage of the user journey. Frequent actions are instant or near-instant. Consequential transitions are more expressive and use timed animations with motion. Nothing moves without purpose.

- **Instant** (0–100ms) — Taps, toggles, selections, anything the user does repeatedly.
- **Swift** (100–250ms) — Contextual transitions, expanding/collapsing, inline feedback.
- **Expressive** (250–500ms) — Page transitions, confirmations, moments of delight.
- Easing curves communicate physicality. Linear motion feels mechanical; use it sparingly.
- Interruption handling matters — animations should be cancelable and reversible.

### On iOS
- UIView spring animations for most transitions. Core Animation for performance-critical paths.
- Match system animation curves where possible to feel at home on the platform.

### On Web
- CSS transitions for simple state changes. Motion libraries for orchestrated sequences.
- `will-change` used intentionally and sparingly — applied before animation, removed after.
- Respect `prefers-reduced-motion`.

---

*This document is updated through the **introspect** skill after significant builds. Principles are added when they prove themselves across multiple decisions — not from a single instance.*
