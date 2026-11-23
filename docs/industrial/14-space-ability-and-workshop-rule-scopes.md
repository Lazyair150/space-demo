# Space abilities and Jar workshop rule scopes

## One skill model for all Space capabilities

Every player-configurable combat capability belongs to the same Space Skill model. This includes projectile weapons, rapid fire, lasers, missiles, shields, drones, reconnaissance, support actions, and combat modifiers. The visible/mechanical form is an effect category, not a separate progression or resource system.

A skill is the immutable semantic binding of:
- Space identity and category (Offense, Defense, Support, Reconnaissance, Utility);
- the category-specific Jar shape affinity supplied by a versioned `SpaceAbilityShapeProfile`;
- a generated Jar order/template identity and its concrete order contract (requirements, order type, Active/Passive lane and cooldown);
- a Space effect definition/version and parameters;
- the selected ship/loadout context.

A skill may execute an instantaneous action, spawn an entity, enable a sustained beam, apply a timed shield, or create a persistent support actor. The Jar order cycle is the resource/admission unit; it is not necessarily one bullet, one laser frame, or one second of a sustained effect. The Space effect executor defines what a successful cycle means.

Jar must never branch on ability category. It sees an opaque order key and its own generated order contract. Space resolves the successful cycle against the frozen skill/effect binding. The order template remains the generator of the order structure; the Space skill gives that generated order a combat meaning. Do not create a parallel Space recipe generator or allow a skill-side cost preview to silently diverge from the exact generated order requirements.

## Ability category ↔ Jar shape semantics

`SpaceAbilityShapeProfile` is a versioned Space-side semantic map from each ability category to one distinct shape in the selected Jar vocabulary. The shape names are authored from the world's actual shape vocabulary; neither category names nor combat semantics are sent into Jar Core.

A skill declares its category and principal shape. Its order requirements must contain a strict majority of that category's mapped shape (more than half of all required Jars), while secondary shapes and liquid-bearing Jars remain valid for mixed-purpose skills. This is a structural affinity, not an exclusive restriction: a shield skill may still require some support-shaped Jars, for example, but its defense-shaped Jar must remain dominant.

The mapping is checked when the Hangar catalog bundle is prepared, before a skill enters the selectable inventory. Changing the mapping or the shape vocabulary requires a new profile version and a compatible skill/order-template revision. The category-to-shape map is Space authoring metadata only; the materialized Jar order still contains ordinary shape/liquid requirements.

The current Space effect registry is Buff-first. It must be generalized into typed Space effect definitions and executors before non-Buff skill content is authored. Do not encode projectiles, beams, drones or reconnaissance as fake BuffDefinitions.

## Two workshop rule scopes

### Workshop-local rules

These describe one workshop in isolation and remain attached to that workshop regardless of role:
- base marks;
- additional marks;
- staging Ban;
- Jar capacity;
- per-liquid capacity and optional aggregate order-staging capacity;
- other local capabilities explicitly supported by the Jar Core contract.

They belong to a versioned `SpaceWorkshopDefinition`. The aggregate `liquidStagingCapacity` remains distinct from the per-liquid `maxLiquids`; when omitted, Core applies its documented fallback.

### Master/Slave relationship rules

These describe how two selected workshops interact:
- role assignment (which local definition is Master and which is Slave);
- one-way Master → Slave resource flow;
- Slave receives resources from Master while in use, not from an independent ship-liquid source;
- exact Jar and free-liquid transfer derived from the B-order solve/resource plan;
- Master staging Ban blocks prohibited liquid from being forwarded;
- Jar-internal liquid remains Jar-owned and must not be misclassified as Master staging liquid;
- generated loose liquid first enters the currently executing workshop staging area and is rejected/discarded according to Core ingress/capacity rules.

The selected roles belong to a versioned `SpaceWorkshopPairDefinition`. The actual transfer, Ban, ownership and resource accounting rules remain enforced by Jar Core. Space does not reimplement them and does not expose designer toggles that can weaken them.

A role swap changes the pair assignment; it does not mutate either workshop's local marks, Ban or capacities.

## Alignment with the Jar Core domain model

This split already exists in the World V2 Core candidate and should be preserved rather than recreated in Space:

- Local workshop capability: `Workshop` owns its resources and capacities; `WorkshopCapability` owns immutable base/additional marks and Ban; `WorkshopRulebook` evaluates local Jar operations; `LiquidRules` owns free-liquid ingress/storage checks.
- Pair/role ownership: `WorkshopRoster` owns the selected Master and Slave references; `MasterSwitchCoordinator` owns role selection; `WorkshopSwitchEvent` and `ResourceTransferrer` own Master replacement migration.
- Pair resource semantics: `WorldOrderOrderedResourceReplay`, `WorldOrderSlaveBoundaryProjector`, and `WorldOrderSymbolicResourceSimulator` model the ordered Master/Slave boundary and exact resource handoff; `OrderResourceSettlementService` settles the role-local staging balances.

Space-side Resources are authoring and freeze-time composition only. They must not become a second implementation of these Core rules.

## Composition

`SpaceWorkshopCombinationDefinition` is the authored build bundle, not a third rule scope. It composes world-level Jar options, an exact-version roster of individual workshop profiles, one exact-version Master/Slave pair selection, and a separate Space-side forecast cost profile. It compiles those inputs into the Core options dictionary and freezes the exact generated options in the battle loadout.

## Active and Passive

- Active is player-requested. The exact demand ID is forwarded to Host/Core; Core decides admission and feasibility.
- Passive is automatically scheduled by Jar Core. It still consumes resources and obeys the same solve/cooldown rules.
- Space owns effect semantics and any future battlefield-context trigger policy. A battlefield condition may request an ability, but it must not duplicate Jar resource feasibility or cooldown logic.
- Active/Passive is independent of ability category. A shield, beam, missile or drone may be Active or Passive.

## Invariants

- No legacy IndustrialRuntime, legacy JarCoreBridge, standalone turn-based IndustrialMain, or old industrial test harness.
- No Jar rule reimplementation in Space; no Space combat/effect implementation in Jar.
- One battle simulation clock and one Host-owned time boundary.
- Frozen exact-version loadout and idempotent cross-domain event/operation identities.
- Do not claim full integration until typed effect executors, durable effect commit and Godot runtime validation are complete.


## Player-owned progression instances

Catalog definitions describe what an item type is; they are not the player's possessions and must not carry player-specific growth. `SpaceOwnedProgressionInstance` is the persistent identity of one acquired copy, and `SpacePlayerProgressionState` is the player-scoped aggregate of unlocks and owned instances.

The same lifecycle applies to ships, universal energy-stone parsers, other production devices, individual workshops, and skills:
- An exact definition version can be unlocked without being owned.
- An owned instance can be acquired only after that exact item-kind/definition/version key is unlocked.
- Multiple instances may reference the same definition version but have independent instance IDs, levels, experience, progression revisions, and growth attributes.
- Growth attributes are opaque Space-owned data interpreted by the subsystem for that item kind. This progression layer does not invent upgrade curves or hardcode item-specific stats.
- Instance updates are revision-checked; stale writes cannot overwrite a newer progression revision. The aggregate has a validated `to_data` / `from_data` round-trip, rejecting duplicate instance IDs, malformed growth payloads, and unsupported schema versions.
- Catalog definitions remain immutable. A frozen battle loadout must eventually include both the exact definition identity and the selected owned-instance snapshot so an in-progress battle is insulated from later upgrades.

The initial aggregate/probe increment has since been extended into the production Hangar path. `SpaceHangarOwnedInventoryBuilder` now projects only acquired instances whose exact definitions resolve; `SpaceHangarSelection` retains instance IDs; and `SpaceHangarOwnedLoadoutAssembler` re-resolves ownership at freeze time. The definition-only selection path remains available for isolated development probes, but `SpaceHangarPreparation.require_owned_instances` defaults to true for production preparation. The owned assembler freezes exact instance snapshots and composes definition + growth into detached runtime profiles.


## Versioned growth curves and calculation boundary

`SpaceProgressionCurveDefinition` is an exact-version, item-kind-specific curve asset, registered and resolved through `SpaceProgressionCurveCatalog`. It defines cumulative total-XP thresholds for entering levels and keyframes for subsystem-owned growth attributes. The shared evaluator supports linear, step, ease-in, ease-out, and smoothstep interpolation, but does not interpret the resulting attribute names or decide what those attributes do in gameplay.

`SpaceProgressionGrowthService` receives an owned instance, its matching curve version, and the new total accumulated XP. It derives the target level and complete growth-attribute snapshot, stamps the exact curve ID/version onto the instance, then produces a revision-incremented instance update. The curve provenance is included in owned-instance snapshots and save/restore data. The player aggregate remains the persistence/commit authority and rejects stale revisions. Once a curve provenance is stamped, the aggregate itself also rejects direct replacement with a different curve ID/version; bypassing the growth service cannot silently rewrite provenance. XP cannot move backwards, and a curve for one item kind cannot update another kind.

Curve assets are authored separately for ships, parsers, production devices, workshops, and skills. They should expose only attributes understood by their owning subsystem. For example, a parser curve may define per-shape processing-rate growth or batch-capacity growth; a ship curve may define hull or mobility growth; a workshop curve may define capacity or capability growth; a skill curve may define effect parameters or order-cost adjustments. These are examples of attribute contracts, not default balance values. No universal level multiplier or upgrade formula is imposed.

A curve version is part of the progression calculation input and must be recorded by the progression/upgrade transaction that applies it. Changing a curve for future progression must not silently rewrite the already stored growth attributes of existing instances. Battle loadouts freeze the resolved instance growth values, not a live reference to the curve asset.


## Subsystem runtime growth adapters and owned Hangar selection

Growth is now applied through `SpaceProgressionRuntimeProfileComposer`. It never mutates a Catalog Resource. Each adapter accepts only a narrow, explicit attribute vocabulary; an unknown key or a key from another item kind rejects composition instead of being silently ignored.

| Owned item kind | Supported growth attributes | Runtime destination |
|---|---|---|
| `ship` | `stoneProgressRateMultiplier` | Multiplies the ship's authored expected stone progress rates for all configured shapes |
| `ore_parser` | `shapeProcessingRateMultiplier`, `progressPerJarMultiplier`, `productionPercentageBonus` | Composes the parser's authored per-shape throughput, per-Jar progress requirement, and production percentage |
| `workshop` | `maxJarsBonus`, `maxLiquidsBonus`, `liquidStagingCapacityBonus`, `additionalMark.<shape>` (0/1) | Composes local workshop capacities and unlocks valid additional marks; the original local Ban and base marks remain intact |
| `production_device` | `runtimeAdd.<field>`, `runtimeMul.<field>` | Adjusts existing numeric root fields in that device's opaque runtime profile; it cannot create unknown fields |
| `skill` | `effectAdd.<parameter>`, `effectMul.<parameter>`, `benefitAdd.<dimension>`, `benefitMul.<dimension>` | Composes Space effect parameters and recalculates the benefit-to-Jar balance report; undercosted growth is rejected |

The key names above are subsystem contracts, not a universal upgrade formula. Curves authored for a particular object must use only attributes supported by its subsystem. Curve keyframes are numeric; discrete workshop mark unlocks use 0/1 keyframes. Capacity bonuses must resolve to integers. A workshop whose staging capacity uses Core's `-1` fallback cannot receive a staging-capacity bonus until its authored definition supplies an explicit capacity. Workshop growth does not change its Ban list or Core pair semantics.

### Owned inventory and loadout freeze

`SpaceHangarOwnedInventoryBuilder` projects the player's aggregate through the exact authored catalogs. Only owned instances with unlocked, resolvable definition versions appear in the production inventory. Repeated copies of the same definition remain separate choices with their own instance IDs, levels, and XP. A workshop combination appears only when the player owns two distinct workshop instances matching the exact Master and Slave workshop definition versions.

`SpaceHangarSelection` and its draft now retain the selected ship/parser/device/skill instance IDs and the two workshop role instance IDs. The Hangar UI displays instance level and identity and passes the selected IDs through the controller. `SpaceHangarPreparation` can be injected with the active `SpacePlayerProgressionState`; when present, its production inventory and freeze path use the owned-instance builder/assembler. Without that state the legacy definition-only development path remains available, but it is not the owned-instance production path.

`SpaceHangarOwnedLoadoutAssembler` re-resolves every selected instance from the player aggregate, checks exact definition identity/version, rejects reusing one owned instance in multiple slots, composes the subsystem runtime profiles, and freezes every selected instance snapshot plus player ID and progression-state revision into the loadout fingerprint. Ship, parser, both workshop instances, production devices, and skills are all included. The loadout snapshot validates that the ownership manifest matches the instances embedded in its selected slots.

Space ownership metadata is deliberately kept outside Jar Core's workshop dictionary. Only the composed workshop's Core-facing local rules/capacities enter `jarWorldOptions.workshops`; the two owned workshop snapshots are stored in the Space-owned workshop-combination selection. The Core still owns all execution, Ban, and Master/Slave transfer semantics.

### Balance and content-authoring constraints

Skill growth can change effect parameters and benefit dimensions independently. The resulting benefit profile is re-evaluated by `SpaceSkillBalanceModel` against the exact Jar order and build context. If the grown effect becomes undercosted relative to its authored Jar requirements, loadout assembly rejects it. The progression layer does not fabricate extra Jar requirements: those must come from the skill's authored Jar order/template contract.

No production curve values, XP rewards, level caps, or final balance progression have been invented in code. The engine supports exact-version curves and subsystem adapters, but production content still needs authored curve Resources and progression rewards chosen by game design. This is a deliberate separation between executable mechanics and balance data.


## Parser runtime ownership and exact instance identity (2026-11-24)

The ore parser is already a Space-owned finite-input production runtime; it is not a missing Core time-driven Producer. Its established pipeline is:

- Energy-stone pickups carry stable pickup IDs, configured Jar-shape identity, and finite volume.
- Space's `SpaceOreParserRuntime` maintains independent per-shape FIFO input, fixed-point rate remainders, and sub-Jar progress.
- The parser consumes only acquired finite volume. A complete threshold creates a pending batch with a stable operation ID.
- `SpaceOreParserJarIngress` submits the batch through `WorldV2ShipHost.ImportProducedJars`.
- Jar Core admits produced empty Jars into its central warehouse and owns warehouse capacity, overflow discard, operation-ID deduplication, and all downstream Jar/workshop rules.
- Space acknowledges a batch only after Core confirms import. A lost receipt is retried with the same operation ID.
- Parser and Jar consume the same Host-authorized whole-millisecond delta; parser processing/import occurs before Jar advances by that exact delta.
- The coordinated checkpoint keeps parser queues/progress/outbox, pickup identities and RNG, Jar resource-ledger receipts, Host clock remainder, and Space run state aligned.

### Exact Owned Instance identity correction

The battle initializer previously constructed the parser runtime ID from `shipWorldId + parser Definition ID`. That made two copies of one Definition indistinguishable at the runtime identity boundary, even though their progression snapshots were independent.

The initializer now derives the runtime identity from `shipWorldId + exact Owned Instance ID` when the frozen parser profile contains `ownedInstance`. It validates item kind and exact Definition ID/version before accepting that identity. Definition-only development fixtures retain an explicit stable fallback identity; production Hangar still requires Owned Instances.

The parser runtime probe now covers:
- two copies of the same exact Definition resolve to different runtime identities;
- a mismatched Owned Instance Definition is rejected;
- Definition-only development identity remains explicit and stable.

This identity is stored in parser checkpoint state and seeds the parser operation-ID namespace, so restore and Core import deduplication remain bound to the installed parser copy.

### Core scope boundary and multi-parser restriction

- Parser execution remains Space-owned. Core receives only completed Jar batches through the discrete warehouse import API; it does not receive stone queues or parser progress.
- Core's current Board Rule Profile consumer remains workshop-only. Parser/Skill/Production Device contributions must not be passed into a workshop RuleContext or silently ignored. The Core-facing Space resolver now rejects non-workshop component contributions before loadout freeze, with an explicit error; it does not pass them to Core to be rejected later. Consumer-specific parser/skill/device profiles remain future work.
- The Board may describe additional decomposition slots, but the current runtime adapter and battle Game own exactly one parser runtime. Multi-parser requires deterministic pickup routing, independent per-instance queues/progress/outboxes/checkpoints, update ordering, and central-warehouse settlement before the count gate can be relaxed.

The matching Core contract is documented in `docs/world-v2/parser-board-slot-runtime-boundary.md` in the Jar Core repository. The identity code and Probe are authored; Godot execution is not claimed.


### Checkpoint migration safety

The identity correction also preserves the old `shipWorldId:parserDefinitionId` identity when restoring a checkpoint that already contains that exact legacy parser runtime ID. This is necessary because a pending batch may already have been committed by Jar Core while its receipt was lost by Space; changing the operation-ID namespace during restore would defeat Core's deduplication and could create a second Jar. The legacy identity is retained only for that restored battle. New battles use the exact Owned Instance namespace. The parser restore path still validates the frozen parser profile and checkpoint contents before accepting state.


## Consumer-routed Board Runtime Profile Set (2026-11-24)

The frozen Board Assignment now has a second, explicit projection: `boardRuntimeProfileSet`. It is not a new rule interpreter and does not broaden Core ingress. It binds each exact installed slot to the already-composed runtime profile consumed by its real subsystem:

| Board component | Consumer | Frozen profile bound |
|---|---|---|
| Workshop | `jar_core.workshop` | Selected workshop runtime data plus Core Board Rule Profile fingerprint |
| Ore Parser | `space.parser` | Exact parser runtime profile, including the frozen Owned Instance |
| Skill | `space.skill` | Jar order request, control area, benefit profile, and Space effect binding |
| Production Device | `space.production_device` | Device runtime profile |

Each manifest entry carries exact slot, component kind, Owned Instance ID, Definition/version, progression revision, and the relevant profile fingerprint. The set is bound to the Board Definition and Assignment fingerprint and has its own canonical SHA-256 fingerprint.

The manifest is assembled only after the parser, workshop, device, and skill runtime profiles have been composed. `SpaceBattleLoadoutSnapshot` rebuilds and validates it against those actual frozen profiles; a missing consumer profile or altered profile fingerprint rejects the loadout.

This is a routing/identity contract, not permission to silently ignore authored Rule Contributions. The Core-facing Rule Profile remains workshop-only. Parser, Skill, and Production Device Rule Contributions still require explicit subsystem semantics and executors before they can be accepted. The manifest makes the consumer boundary explicit so future profile extensions cannot accidentally share the Core workshop execution context.
