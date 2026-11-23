# Stage Structure and Art Direction

## Why the endless arena is not the campaign

The current Spawner is an endless four-beat loop (warmup, pressure, elite, rest). Keep it as an arcade/endless mode, but do not let it stand in for campaign progression. A campaign is a finite, authored sequence of missions with a clear objective, encounter beats, completion boundary, unlock chain, and reward settlement.

## Stage hierarchy

- Campaign: a thematic arc / sector containing ordered stages.
- Stage: a finite mission with a stable ID and definition version.
- Encounter beat: one authored combat segment inside a stage. Beats define composition, pacing, rest windows and optional duration/elite/boss markers.
- Objective: eliminate all, survive duration, protect target, collect resource, or boss encounter.
- Reward settlement: emits a result payload to progression; it does not directly mutate Jar World or owned instances.
- Endless: a separate replayable mode that continues the existing four-beat loop.

## Growth adaptation

Every stage authors its recommended loadout level and an optional bounded difficulty profile. The profile compares the average level of the exact owned instances frozen into the battle loadout against the recommendation. The finite encounter director carries the resulting encounter-scale proposal with each authored beat. The live Spawner applies deterministic ceiling scaling to authored enemy counts only; health and speed are separate future tuning channels. It never changes the player's curve, owned instances, Jar definitions, workshop bans, order costs, or skill balance.

A stage can be deliberately fixed-difficulty by setting both scale bounds and per-level coefficients to neutral values. This avoids silently rubber-banding every encounter. The recommended level is also useful for Hangar warnings and stage unlock requirements.

## Campaign progression

Stage completion must be a separate durable aggregate from transient combat state. A successful clear records exact stage ID/version, best result, and reward settlement identity. A failed run does not unlock the next stage. Reward settlement must be idempotent and commit once; it may grant XP/resources/unlocks but must call the existing progression services rather than editing owned-instance fields directly.

## Presentation and HUD

The HUD should display campaign / stage / objective / encounter beat, objective progress, and stage completion state. The endless mode retains wave and segment labels. Stage transitions should not be represented as infinite wave increments.

## Art direction

Use a coherent vector sprite language: deep-space navy silhouettes, restrained cyan/amber energy accents, clear negative space, thick readable outlines, and simplified geometry that survives 32–128 px display. Keep gameplay sprites separate from Hangar category icons. SVG assets are source artwork and should remain editable; runtime animation, hitboxes and collision geometry remain Godot scene responsibilities.

## First authored campaign slice

Build the first campaign as a short onboarding arc:
1. **Drift Perimeter** — movement / basic chaser engagement.
2. **Signal Interference** — mixed chasers and shooters, introduces ranged pressure.
3. **Ore Convoy** — resource pickup and parser throughput under combat pressure.
4. **Broken Relay** — elite encounter and controlled rest window.
5. **Warden of the Rift** — boss capstone, unlocks the next sector.

The current implementation now includes `SpaceStageDefinition`, `SpaceStageCatalog`, a five-stage `Rift Frontier` catalog, `SpaceStageProgressionProfile`, and `SpaceCampaignProgressState` persistence in `GameState`. `SpaceStageModelProbe` covers catalog validation, linear unlock progression, idempotent clear recording, save/restore, loadout-level comparison, encounter-director restore, collect-resource progress, and exact boss-definition matching. The Spawner now has two isolated modes: no injected stage director means the legacy endless four-beat loop; a pre-tree injected director runs the finite authored beat list and stops at its terminal boundary. `Game.configure_battle_stage()` freezes the exact stage against the already-frozen owned-instance loadout. `SpaceStageObjectiveRuntime` separately tracks eliminate-all, survive-duration, collect-resource, protect-target and boss contracts; accepted energy-stone pickup volume feeds collect-resource progress. Encounter completion alone does not award a clear: Game emits `stage_completed` only after both encounters and the objective are complete. Finite-stage checkpoints use a distinct runtime envelope containing exact stage ID/version, exact frozen loadout identity, director state, objective state and completion flags. Capture is permitted only during the enemy-free inter-beat window, after the director has advanced to the next beat; this avoids silently losing live enemy actor state. Resume requires the exact stage asset and loadout fingerprint and rejects completed/non-active stage checkpoints. Boss defeat and protected-target binding expose explicit APIs, but the first campaign still lacks the actual boss actor/catalog and protect-target actor. Stage selection UI and idempotent reward settlement remain to be connected; the coordinated checkpoint capture/restore boundary is now implemented for enemy-free inter-beat saves.

## First SVG concept batch

The editable SVG concept library is under `assets/sprites/`: player frigate, scout, bomber, elite warden, iron asteroid, small/large energy stones, rift gate, relay station and support drone. These are concept assets, not yet gameplay scene replacements. See `assets/sprites/README.md` for roles and art direction.

## Persistent campaign state

`SpaceCampaignProgressState` stores exact stage ID/version, clear result and reward settlement identity. `GameState` saves it separately at `user://space_campaign_progress.cfg`, not inside transient wave state or the Jar checkpoint. A stage clear is idempotent per exact stage version. The reward settlement ID is recorded as a durable identity; actual reward application is deliberately not implemented until the campaign result boundary can atomically coordinate XP, resources and unlocks.


## Roguelike individual library and power budgets

- Parser, individual workshop, and skill definitions are eligible reward kinds. The library stores versioned pools per kind; a pool entry references an exact definition ID/version and carries rarity, normalized power score, weight, and tags. Each pool pins an exact subsystem power-model ID/version. That model normalizes the owning subsystem's named metrics (with authored bounds, direction and weights) into a score; it rejects missing/out-of-range metrics. The pool then checks the score against the rarity band, and the reward service verifies both the exact model identity and the model-derived score before acquisition.
- Each rarity has an authored inclusive power band. Pool validation rejects entries below or above that band, invalid weights, duplicate exact definition identities, missing rarity bands, and unsupported item kinds.
- Weighted rolls are deterministic under the supplied RNG seed and can filter rarity, tags, and already-seen definition identities. The result is only a reward candidate; it does not grant ownership or mutate player progression.
- Acquisition remains the responsibility of SpacePlayerProgressionCatalogService and SpacePlayerProgressionState: the exact catalog definition must be unlocked/resolved before a new SpaceOwnedProgressionInstance is acquired. Repeated copies retain separate instance IDs and growth.
- validate_effective_metrics() and validate_effective_power() recheck a grown instance's subsystem metrics/score against its exact pool entry and rarity band. The subsystem-specific progression curve still owns how growth attributes translate into power; the pool does not invent a universal growth formula.
- SpaceHangarCatalogBundleResource can reference the shared individual library and exposes pool metadata to Hangar inventory. The reference is optional until actual production pools and exact definition versions are authored; no fake balance numbers or empty production loot tables are shipped.
- SpaceRoguelikeIndividualLibraryProbe uses synthetic fixtures only to test deterministic rolls, filtering, duplicate identity, and under/over-budget rejection. It is included in the broader ownership probe but has not been run in Godot.

## Subsystem-derived power evaluation and player-choice offers

- Added `SpaceIndividualPowerEvaluator` adapters for parser, workshop and skill definitions. Parser metrics come from production percentage, per-shape processing rates and progress-per-Jar thresholds; workshop metrics come from Jar/liquid capacities, explicit-vs-Core-fallback staging, marks and Ban count; skill metrics come from the existing benefit-to-Jar difficulty model, cooldown frequency and actual Jar/liquid/shape requirement counts.
- The evaluator does not define shared balance weights or invent production score ranges. Each exact `SpaceIndividualPowerModelDefinition` supplies metric bounds, direction and weights. Out-of-range or missing dimensions reject evaluation.
- Added `SpaceRoguelikeIndividualPoolEntryBuilder` so production pool entries can be generated from an exact catalog definition and evaluation report. Parser entries pin the shape vocabulary used for evaluation; workshop entries pin both shape and liquid vocabularies for Ban validation; skill entries pin the benefit metrics and battle context used by the existing skill balance model.
- Production pools default to `require_definition_evaluation=true`. At reward acquisition, the service resolves the exact parser/workshop/skill definition again and recomputes the score from the stored evaluation inputs. A candidate is rejected if its score or metric payload cannot be reproduced from that definition. Synthetic probe pools explicitly disable this production guard and are not shippable content.
- Weighted draws now aggregate eligible entry weights across every matching pool rather than choosing a pool uniformly first. This prevents an empty filtered pool from hiding valid entries in another pool.
- `SpaceRoguelikeIndividualOfferService` produces up to eight distinct exact-definition choices without changing ownership. Each offer retains its own pool/model identity and rarity band; it never compares raw scores across different models. Only `acquire_selected` transfers the chosen candidate into the progression aggregate.
- The offer and evaluator probes are wired into `SpaceHangarCatalogOwnershipProbe`, including deterministic selection, unique candidate identities, exact-catalog acquisition and subsystem-derived metrics. They are authored, not executed in Godot.
- No production parser/workshop/skill power-model Resources, rarity budgets, or loot pools are authored yet. Those require real production definition data and balance review; the new builder/evaluator is the safe path for generating them without guessing.

- Added stable reward-offer IDs and a persisted acquisition receipt ledger to player progression schema 2. The offer ID itself is a single-use receipt across every candidate index; the same offer cannot grant multiple choices, and replaying it with a different proposed instance ID is rejected. Schema-1 progression saves migrate forward with an empty receipt ledger, preserving existing owned instances.
- Protected-target destruction now produces an explicit failed objective state. Game emits `stage_failed`, ends the active battle lifecycle, and rejects restoring a failed objective checkpoint. This makes the failure observable; a production stage-result/retry UI still needs to consume the event.

- Finite-stage victory now requires a preconfigured durable settlement callback. The Hangar launcher supplies a unique settlement identity; GameState writes a detached campaign-progress candidate through a pending/backup replacement, publishes the new unlock ledger only after persistence succeeds, and attempts backup recovery on startup after an interrupted replacement. A failed write faults the stage instead of announcing a victory that cannot be resumed/unlocked.
- This transaction currently commits the campaign clear record only. Stage reward payload application across campaign and owned-progression ledgers is still a separate unfinished transaction; no item rewards are granted by the clear callback yet.
- Workshop power evaluation normalizes `liquid_staging_capacity=-1` (the documented Core fallback sentinel) to zero explicit capacity and records `uses_core_staging_fallback` separately; it never treats the sentinel as a negative physical capacity.
- The same durable settlement boundary is restored for resumed finite-stage battles: the exact stage definition and protected-target binding are passed into checkpoint restore, then a fresh single-use settlement ID is injected before the resumed scene is attached.
- Hangar now renders the authored Rift Frontier campaign picker, displays objective/recommended level/duration/briefing/reward preview, defaults to the first unlocked stage, and disables locked stages using exact cleared stage-version keys. It exposes the exact selected stage resource to the owning launch flow; this screen still does not instantiate the battle scene itself.
