# World V2 resource HUD and shape visual language

Status (2026-11-25): the ship-resource HUD observer, shape glyph/color mapping, workshop summaries, demand/cooldown/session summaries, and snapshot-delta feedback are implemented. The cross-repository run `45438436612` passed the Godot project import and integration probes at Space `74a93ed` against Core `b342259`. Remaining work is presentation polish (production art, editor-authored palette, real combat capture/manual visual review), not a missing resource-ownership or solver path. Latest PR head `d9e1d4b681163697f6623b17ccd077edc0abfb51` includes documentation-only status cleanup after the test type annotation change; exact-head verification remains pending. This remains a presentation contract; it does not change Jar Core rules, resource ownership, feasibility, or Space balance.

## Player-facing information hierarchy

The combat HUD keeps survival information (health, wave, score) in its existing fixed positions. Directly below the upper-left status row, a persistent **JAR resource strip** acts as the resource-bar counterpart to health/shield/energy HUD meters: it remains visible during combat without requiring a click. It shows exact ship-level Jar count split by shape glyph, exact ship-liquid counts and used/capacity, concise Master/Slave Jar-and-liquid staging totals, the one-way Master → Slave direction, and Host lifecycle state. Ship-level capacity is not exposed by the snapshot, so this strip deliberately shows quantities and shape composition rather than inventing a percentage/fullness meter. Clicking the strip opens a read-only detail panel containing:

- ship resource Jars rendered as individual compact tiles, each showing its shape glyph/color, exact Jar identity when exposed, liquid fill strip, empty/filled state, and marked indicator; inventories over the visible tile budget show an explicit remaining count;
- ship resource liquids by exact liquid key and exact used/capacity; the central LiquidWarehouse snapshot is a separate account and is not presented as ship-owned stock;
- separate Master and Slave workshop cards with shape-affinity borders, Jar occupancy/capacity, shape marks, individual Jar tiles, liquid staging meters and explicit staging-Ban warnings; the Master → Slave transfer direction is shown between the cards;
- selected demand identity, required Jar shapes/liquid-bearing requirements, cooldown state, and active session step counts.

Two skill-like order docks remain visible without opening the detail panel:
- **Active orders / active skills** occupy the bottom-right skill-bar position, leaving bottom-left objective text unobstructed. Each slot shows its authored primary-shape accent, required-shape glyphs, cooldown or live execution progress, and an explicit Start button. The button forwards only `StartActiveDemand(demandId)` through `WorldV2ShipHost`; Core remains the sole authority for feasibility, admission, and execution. A rejected start is shown as a reason, not reinterpreted by the HUD.
- **Passive orders / passive skills** occupy a separate upper-right badge rail below the survival HUD. They show their own shape identity and cooldown state, but do not display an activation button: the Passive area remains scheduler-owned.
- The detailed order section repeats the Active/Passive separation. Neither dock derives the primary shape from the first requirement; it uses only the Space-owned `primaryShape` presentation metadata.

The compact state remains visible without opening a menu; the detail panel is on-demand so it does not permanently cover the combat play area. The observer does not mutate resources or own simulation time; its sole command is the explicit Active-order trigger.

## Shared shape language

The current World V2 sandbox authors two shape names (圆罐 and 方罐). The provisional palette also reserves two additional archetypes (三棱 and 长条) so later authored shapes can be colored without changing the presentation system:

| Shape | Glyph | Color |
| --- | --- | --- |
| 圆罐 / 圆形舱段 | ● | cyan-blue |
| 方罐 / 方形舱段 | ■ | amber |
| 三棱类形状 | ▲ | violet |
| 长条类形状 | ▬ | mint |

`ShapeVisuals.gd` owns this mapping and a neutral fallback for unknown shapes. The helper is presentation-only. The same shape key uses the same color in resource inventory, workshop cards, production lines, and order requirement tokens. New shapes can be added to this mapping without changing Jar's shape vocabulary or solver.

Color is never the only carrier of meaning: each token also displays a distinct glyph and the shape's authored name. The current four-color set is provisional and can later move into an editor-authored palette Resource without changing the consuming UI components.

## Workshop tendency color

A workshop card's accent is a weighted blend of its existing shape marks: each `baseMarks` entry has weight 2 and each `additionalMarks` entry has weight 1. This gives the player a fast visual impression of the workshop's shape bias while retaining the exact mark names beside it.

This blend is not a new workshop stat and must never be consumed by compatibility checks, Jar operations, selection, or balancing. Ban remains a separate staging-ingress warning inside its workshop card and is never encoded as a shape color.

## Resource meters and truthful quantities

- Workshop liquid staging is shown as a meter only against that workshop's own `maxLiquids`; each liquid is measured independently.
- Ship-level liquid inventory is read from snapshot.shipLiquidInventory.balances and shows exact counts plus used/capacity; snapshot.resourceLiquids remains the separate central LiquidWarehouse account. No percentage bar is inferred.
- Ship resource Jars and workshop Jars are separate groups; never combine their counts.
- A Jar with liquid remains a Jar resource, and its fill state is shown as a secondary detail. This does not move liquid ownership or make Jar contents equivalent to free workshop/ship liquid.

## Order presentation

Each order demand displays its exact required shape as a colored glyph token; a liquid-bearing requirement adds the exact liquid name. The Space-owned skill/order binding may author a `presentation.primaryShape` independently of the nested Jar order contract. The frozen loadout validates that this primary shape is one of the Jar order's required shapes. The HUD resolves this metadata through the frozen loadout and accents the order heading/primary-shape token; Jar still receives only its unchanged `jarOrder` data.

## Data ownership and update policy

`SpaceJarHudObserver` reads detached state through `WorldV2ShipHost.GetWorldSnapshot()`. Its only command is an explicit Active-demand trigger forwarded through `WorldV2ShipHost.StartActiveDemand()`; it does not infer feasibility, calculate costs, mutate resources directly, or advance time. Core decides whether a requested demand can start. It polls at a low UI cadence and rebuilds only when the detached snapshot changes. The component uses `PROCESS_MODE_ALWAYS` so the information remains inspectable while the combat SceneTree is paused; the underlying Host lifecycle remains the authority for whether simulation can advance. Between distinct snapshots it compares exact Jar counts/fill counts, ship-inventory and workshop-staging liquid totals, lifecycle state, demand cooldown transitions, and active-session step totals. It never treats central LiquidWarehouse balances as ship-owned stock. It emits a short, coalesced toast and a brief tint pulse on the compact JAR control. The first snapshot after startup/reconnect establishes a baseline and never fabricates a gain event. Clock-only changes update the time label without rebuilding the inventory controls, avoiding repeated UI churn during steady simulation. Workshop liquid meters use a presentation-only 80% caution tint and a full-capacity label; this is not a Core threshold or an admission rule. These cues are observational only; they do not infer feasibility or trigger commands.

Unavailable, disposed, or not-yet-started worlds show an explicit unavailable state rather than fabricated zero inventory. The panel is hidden by default and toggled by the compact summary control.

## Interaction and accessibility

- Summary control has a clear expanded/collapsed state.
- Hover tooltips explain that shape colors are identification aids, not rules.
- Shape name and glyph accompany every color.
- Ban and warning text remain explicit; color is supplementary.
- Detail view does not block the center combat path and can be collapsed immediately.
- Resource transfers, workshop replacement, and pause remain owned by their existing command/lifecycle boundaries. The Active slot is the one explicit order action and delegates admission to Core; Passive slots remain observational.

## Current implementation boundary

Implemented on the branch:
- shared shape glyph/color palette;
- color-coded shape tokens in the industrial presentation components;
- optional Space-owned `primary_shape` metadata on skill/order definitions, shown in Hangar selection, frozen outside the Jar order payload and validated against its requirement shapes;
- workshop tendency accent as separate Master/Slave cards, an explicit one-way Master → Slave transfer cue, and per-liquid staging meters where capacity is explicit;
- combat HUD observer for the active World V2 Host snapshot; ship liquid counts and capacity are projected from the dedicated shipLiquidInventory account, not the central resourceLiquids warehouse;
- individual responsive Jar tiles in ship inventory and each workshop, with a bounded visible count and an explicit overflow count;
- snapshot-delta feedback for Jar acquisition/consumption, fill changes, ship/workshop liquid changes, lifecycle transitions, order cooldown transitions, and active-session progress;
- clock-only snapshot updates no longer rebuild inventory controls; workshop meters add a presentation-only 80% caution state and explicit full-capacity label;
- pure aggregation and shape-vocabulary checks in `tests/space_jar_hud_feedback.gd`;
- order requirement shape tokens and read-only demand/cooldown/session summary.

Not yet authored:
- final production art/icons and sound;
- editor-configurable palette Resource;
- authoring primary shapes on production skill Resources and reviewing their visual hierarchy;
- responsive art review against real combat captures and a manual Godot play pass.

Cross-repository verification (2026-11-25): Core PR #60 head `b342259fe04363386085dc9a4ca995112954ed43` passed run `45437911516` (841 tests, 0 failures). Space PR #2 integration run `45438436612` built the exact Core Bridge, built Space, imported/parsed the Godot 4.7.1 .NET project, and passed parser ingress, runtime, lifecycle, fault, disposed-command, faulted-command, and snapshot-isolation probes. The snapshot-isolation probe now verifies both the central warehouse and ship-owned liquid inventory are detached. Both PRs remain Draft/Open/unmerged.