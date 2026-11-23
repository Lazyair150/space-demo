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

The current implementation now includes `SpaceStageDefinition`, `SpaceStageCatalog`, a five-stage `Rift Frontier` catalog, `SpaceStageProgressionProfile`, and `SpaceCampaignProgressState` persistence in `GameState`. `SpaceStageModelProbe` covers catalog validation, linear unlock progression, idempotent clear recording, save/restore, loadout-level comparison, encounter-director restore, collect-resource progress, and exact boss-definition matching. The Spawner now has two isolated modes: no injected stage director means the legacy endless four-beat loop; a pre-tree injected director runs the finite authored beat list and stops at its terminal boundary. `Game.configure_battle_stage()` freezes the exact stage against the already-frozen owned-instance loadout. `SpaceStageObjectiveRuntime` separately tracks eliminate-all, survive-duration, collect-resource, protect-target and boss contracts; accepted energy-stone pickup volume feeds collect-resource progress. Encounter completion alone does not award a clear: Game emits `stage_completed` only after both encounters and the objective are complete. Finite-stage checkpoints use a distinct runtime envelope containing exact stage ID/version, exact frozen loadout identity, director state, objective state and completion flags. Capture is permitted only during the enemy-free inter-beat window, after the director has advanced to the next beat; this avoids silently losing live enemy actor state. Resume requires the exact stage asset and loadout fingerprint and rejects completed/non-active stage checkpoints. Boss defeat and protected-target binding expose explicit APIs, but the first campaign still lacks the actual boss actor/catalog and protect-target actor. Stage selection UI, checkpoint restore, and reward settlement remain to be connected.

## First SVG concept batch

The editable SVG concept library is under `assets/sprites/`: player frigate, scout, bomber, elite warden, iron asteroid, small/large energy stones, rift gate, relay station and support drone. These are concept assets, not yet gameplay scene replacements. See `assets/sprites/README.md` for roles and art direction.

## Persistent campaign state

`SpaceCampaignProgressState` stores exact stage ID/version, clear result and reward settlement identity. `GameState` saves it separately at `user://space_campaign_progress.cfg`, not inside transient wave state or the Jar checkpoint. A stage clear is idempotent per exact stage version. The reward settlement ID is recorded as a durable identity; actual reward application is deliberately not implemented until the campaign result boundary can atomically coordinate XP, resources and unlocks.


## Roguelike individual library and power budgets

- Parser, individual workshop, and skill definitions are eligible reward kinds. The library stores versioned pools per kind; a pool entry references an exact definition ID/version and carries rarity, normalized power score, weight, and tags.
- Each rarity has an authored inclusive power band. Pool validation rejects entries below or above that band, invalid weights, duplicate exact definition identities, missing rarity bands, and unsupported item kinds.
- Weighted rolls are deterministic under the supplied RNG seed and can filter rarity, tags, and already-seen definition identities. The result is only a reward candidate; it does not grant ownership or mutate player progression.
- Acquisition remains the responsibility of SpacePlayerProgressionCatalogService and SpacePlayerProgressionState: the exact catalog definition must be unlocked/resolved before a new SpaceOwnedProgressionInstance is acquired. Repeated copies retain separate instance IDs and growth.
- validate_effective_power() rechecks the grown instance's effective power against its exact pool entry and rarity band. The subsystem-specific progression curve still owns how growth attributes translate into power; the pool does not invent a universal growth formula.
- SpaceHangarCatalogBundleResource can reference the shared individual library and exposes pool metadata to Hangar inventory. The reference is optional until actual production pools and exact definition versions are authored; no fake balance numbers or empty production loot tables are shipped.
- SpaceRoguelikeIndividualLibraryProbe uses synthetic fixtures only to test deterministic rolls, filtering, duplicate identity, and under/over-budget rejection. It is included in the broader ownership probe but has not been run in Godot.
