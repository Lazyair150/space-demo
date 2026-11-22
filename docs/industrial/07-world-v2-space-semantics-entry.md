# World V2 × Space — semantic design entry

## Why this phase starts here

The Jar System's World V2 resource/execution lifecycle is now sufficiently specified to serve as an independent domain. The next task is not to wire its API into the old Space UI. It is to decide what the Jar world means inside the Space game, which system owns each state, and which events cross the boundary.

This document is a design entry point, not an implementation claim. It deliberately leaves unresolved gameplay rules unresolved.

## Current repository facts

- Space already contains an isolated World V2 RuntimeNode and a Godot Bridge consumer path for initialization, logical-time advancement, commands, snapshots, fault handling, and disposal.
- The current main industrial scene and the IndustrialRuntime autoload still point to the legacy industrial implementation. The World V2 Runtime is not yet the production consumer of the actual industrial UI.
- World V2 commands and snapshots have been exercised by isolated probes; those probes do not establish the final player-facing semantics.
- The legacy industrial loop has old order completion, reward/material, wallet, save, and combat-upgrade relationships. These are historical behavior, not approved migration requirements.
- The old Jar module may be removed as a whole after the new domain integration is defined. It must not be treated as the implementation target for World V2.

## Stable Jar-side contract

The Space domain may rely on these facts without re-implementing them:

1. A World V2 instance owns its own resource area, ship liquid inventory, workshop roster, demand board, solver, admission, execution sessions, logical clock, and resource ledger.
2. Master and slave are fixed roles in one roster. A workshop object can leave a role and become a spare; roles do not swap identities.
3. Master replacement is a timed world operation. Target master prefill is withdrawn from ship liquid inventory up to the target master's staging capacity. If replacement is cancelled before commit, the prefill is rolled back.
4. On successful master replacement, the old master's unconsumed prefill is returned to ship liquid inventory. Ship-capacity overflow is explicitly discarded and recorded.
5. A-class orders use only the master. B-class orders may use the slave, and the slave's liquid comes only from the one-way master-to-slave transfer for that order.
6. Free liquid left in order scopes is settled back to ship liquid inventory at terminal settlement, subject to capacity. Liquid incorporated into a jar remains inside that jar.
7. World V2 owns order feasibility, admission, resource reservation, execution, interruption settlement, and logical-time progression. Space must not duplicate those rules.
8. World V2 does not own player health, enemy damage, combat score, reward policy, wallet currency, mission outcome, or scene navigation.

## Space-side semantic questions to settle

These questions are intentionally open. No code should encode an answer until the semantic contract is approved.

### A. What is the Jar world in the game?

Choose the actual player-facing role:
- a persistent industrial subsystem that runs while the player is elsewhere;
- a station/room activity entered explicitly by the player;
- a tactical support system that can affect a live combat encounter;
- a progression/economy layer between encounters;
- or a combination with explicit mode boundaries.

This choice determines whether Jar logical time advances during combat, only while its scene is active, or under a separate simulation policy.

### B. What causes entry and exit?

Define:
- which game event opens the Jar interface/world;
- whether opening it pauses combat, transitions to another scene, or overlays the current scene;
- whether closing it leaves the Jar world running;
- what happens if the player exits during an active order or workshop replacement;
- whether the world can be entered again with active work in progress.

The UI transition itself must not be confused with a master/slave workshop replacement. The latter is a domain operation inside the Jar world.

### C. What crosses the resource boundary?

Define the canonical resource mapping:
- which Space-owned resources can become Jar ship liquid or jar inputs;
- whether enemy drops, energy stones, salvage, or other pickups are converted at all;
- whether conversion is immediate, queued, capped, or performed at a station;
- whether Jar outputs remain Jar-owned inventory or are explicitly exported to Space;
- what happens when either side is at capacity.

Do not assume the legacy ore/material/wallet mapping remains valid. The new Jar ship liquid inventory is not automatically the Space wallet.

### D. What does Jar completion mean to Space?

Decide whether a completed demand:
- only changes Jar-owned inventory and workshop state;
- emits a domain fact that Space may interpret;
- creates a mission objective result;
- unlocks a recipe/equipment/progression item;
- or has no direct combat consequence.

If a reward exists, Space owns reward policy and idempotency. Jar should report a completed domain result, not grant combat currency or mutate player stats.

### E. How should time and interruption work?

Define the relationship between:
- Space simulation time;
- Jar WorldClock logical time;
- pause/menu/loading states;
- scene-tree visibility and process mode;
- active order execution;
- workshop replacement.

A scene being hidden is not itself a domain pause command. The integration layer must explicitly translate approved game-state transitions into Jar clock policy.

### F. What is saved, and by whom?

Separate:
- Space save-game identity and versioning;
- Jar configuration identity/fingerprint;
- Jar active execution checkpoint;
- Space-owned player progression and unlocks.

A Jar execution checkpoint is not a complete Space save and does not reconstruct arbitrary Space state. The save coordinator must define atomicity and recovery if one subsystem restores while the other fails.

## Proposed boundary shape (not yet an API commitment)

Use an explicit integration coordinator owned by Space:

- Space sends commands/intents such as enter/leave, approved resource import/export, and clock policy changes.
- Jar exposes detached snapshots and domain outcomes through its ApplicationService/Bridge.
- Space subscribes to stable domain facts (e.g. order completed, resource export requested) and decides game consequences.
- Jar never calls Player, Enemy, GameState, wallet, damage, reward, or scene-tree APIs.
- The coordinator owns cross-domain idempotency keys and save orchestration; neither domain reaches into the other's internal objects.

No direct references from Jar Core to Godot nodes or Space scripts are allowed.

## Required semantic artifacts before implementation

1. A context map naming Space and Jar bounded contexts, their state owners, and the integration coordinator.
2. A lifecycle state machine for entering, running, pausing, leaving, faulting, and restoring the Jar world.
3. A resource import/export contract with units, caps, ownership, rejection, and ledger provenance.
4. A completion/event contract distinguishing Jar completion from Space reward/mission consequences.
5. A time policy specifying exactly when Jar logical time advances.
6. A save/restore transaction design covering partial failure and active execution checkpoints.
7. A migration plan that replaces the legacy industrial consumer without carrying forward unapproved legacy semantics.

Only after these artifacts are approved should the production scene, autoload, and player-facing UI be migrated from legacy IndustrialRuntime to the new World V2 Runtime.

## Explicit non-goals for the first integration pass

- No migration of old order rewards, materials, ore wallet, attack upgrades, or damage bonuses.
- No coupling Jar order completion directly to enemy/player health or combat score.
- No automatic conversion of combat drops into liquid without an approved resource mapping.
- No attempt to make the Jar world responsible for Space mission success/failure.
- No deletion of the legacy implementation until the replacement flow and save compatibility policy are agreed.
