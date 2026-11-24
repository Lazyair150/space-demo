# Space / World V2 documentation index

This directory contains the current World V2 ↔ Space integration contracts. The current local playable entry path is documented in the repository root [README](../../README.md).

## Current integration and ownership

- [07 — Space semantics entry](07-world-v2-space-semantics-entry.md): ownership boundaries, stable Jar contract, and Space-side semantic decisions.
- [08 — World host and simulation clock](08-world-lifecycle-host-and-clock-contract.md): host lifecycle, simulation-time authority, pause/suspend/disposal.
- [09 — Resource boundary and domain events](09-resource-boundary-and-domain-events.md): resource ownership, order completion events, Space effect application.
- [10 — Pre-battle loadout and order-effect binding](10-prebattle-loadout-and-order-effect-binding.md): immutable player build, skills, effect binding, persistence boundary.
- [11 — Real resource contract audit](11-real-resource-contract-audit.md): resource-account and cross-boundary audit.
- [12 — Order funnel and skill resource-cost semantics](12-order-funnel-and-skill-resource-cost-semantics.md): skill costs and order ingress semantics.
- [13 — Resource HUD and shape visual language](13-resource-hud-and-shape-visual-language.md): observable resource presentation and Jar-shape visual mapping.
- [14 — Space ability and workshop rule scopes](14-space-ability-and-workshop-rule-scopes.md): Space-owned ability policy versus workshop-local rules.

## Integration record

- [Cross-repository integration and cleanup checkpoint](../execution/2026-11-24-cross-repo-integration.txt): exact Core/Space revisions, CI evidence, known validation limits, and cleanup decisions.
- [Execution baseline](../execution/2026-11-23-next-phase-execution-baseline.md): chronological planning and implementation history; use the checkpoint above for current verification facts.

## Scope exclusions

- Manual workshop replacement is an isolated future module and is not required for the current playable path.
- Space balance/catalog production authoring and complete player-facing visual polish remain later content work.
- Jar solver, feasibility, resource accounting, and order execution rules remain Core-owned; do not duplicate them in Space.
