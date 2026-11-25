# Game Runtime Lifecycle, Time Authority, Pause, and SceneTree Contract

Status: architecture contract plus first combat-pause integration. This document records the current Godot runtime ownership boundaries and the required target structure. It is not a claim that every legacy scene has already been migrated.

## 1. Separate application navigation from simulation lifecycle

Do not represent all runtime state with one boolean such as `is_running`. There are two independent dimensions:

### Application screen

`MENU → HANGAR → BATTLE → GAME_OVER` is navigation state. `INDUSTRIAL` is a separate application screen backed by its own long-lived IndustrialRuntime.

Changing screen is a scene/application-flow operation. It is not a simulation pause operation.

### Simulation state

The combat simulation has the following lifecycle:

- `PREPARING`: frozen loadout and checkpoint are being validated before the combat scene enters the SceneTree.
- `RUNNING`: Space physics and its single Jar time-forwarding step are authorized.
- `PAUSED`: no combat physics step is authorized; the World V2 ShipHost is also in its Paused lifecycle state.
- `RESUMING`: synchronous restoration of the Host and SceneTree pause gates; this is a transition, not a frame-advancing state.
- `ENDED`: the battle has terminated and its ship world is disposed.
- `RESUME_READY`: restoration has completed, both Host and SceneTree pause gates are closed, and an explicit player confirmation is required.
- `FAULTED`: a runtime fault has latched; no further simulation step is accepted.

A pause reason is metadata, not another running state: `PLAYER`, `WINDOW_FOCUS_LOST`, or a future explicit system reason. Losing focus pauses automatically; regaining focus does not automatically resume. The player must explicitly resume.

## 2. What Godot pause actually freezes

The authoritative in-scene gate is `SceneTree.paused`.

- Nodes with `PROCESS_MODE_PAUSABLE` (or `INHERIT` under a pausable parent) stop their idle, physics, and input processing while the tree is paused.
- `PROCESS_MODE_ALWAYS` continues processing. Reserve it for pause controls and UI that must remain interactive.
- `PROCESS_MODE_WHEN_PAUSED` is for narrowly scoped paused-only UI/diagnostics.
- `PROCESS_MODE_DISABLED` stops processing regardless of tree pause.
- The SceneTree root defaults to `PROCESS_MODE_PAUSABLE`; autoloads and the active scene normally inherit that policy unless they explicitly override it. Thus the combat pause also suspends pausable autoload processing such as the IndustrialRuntime accumulator. This is intentional for the current single-active-screen application.
- Physics simulation and collision callbacks for the paused gameplay tree stop with the tree pause.
- A `Timer` node must inherit the gameplay pause policy. Do not enable its process-while-paused behavior for combat scheduling.
- `SceneTree.create_timer(seconds)` defaults to processing while paused. Combat delays must explicitly use `create_timer(seconds, false)`. A UI-only animation may deliberately use an always-processing timer, but it must be owned by UI and documented.
- Tweens/AnimationPlayers attached to gameplay nodes inherit their owner process policy. Pause-menu animation is UI-owned and may continue.
- Standard Godot audio player nodes pause their current stream with SceneTree pause and resume automatically. Bus effects, externally managed audio, or deliberate UI audio that must continue need an explicit policy.

Changing `Engine.time_scale` is not a pause API. Keep it at the normal global scale for this architecture. Jar logical speed ratios are owned by the Jar WorldClock; they must not alter Space physics or the Space-to-Jar delta. A true combat pause uses the pause gate and Host lifecycle transition, not a zero speed ratio.

## 3. Combat time authority: exactly one path

The only production Space-to-Jar time ingress is:

`Game._physics_process(delta)`
→ `WorldV2ShipHost.AccumulateSpaceSimulationDelta(delta)`
→ Space-owned parser/effect work using that exact whole-millisecond delta
→ `WorldV2ShipHost.AdvanceSpaceSimulationMilliseconds(the_same_delta)`
→ `WorldV2RuntimeNode.AdvanceWorldTime(delta)`
→ Jar Core WorldClock.

The Host owns the fractional-millisecond remainder and enforces the prepared-step/forwarded-step pair. Save capture is legal only between completed steps. The order/effect dispatcher drains only after the Jar step succeeds.

Production `WorldV2ShipHost` creates `WorldV2RuntimeNode` with `AutoAdvance = false`; the standalone runtime probe may use the Runtime node's independent auto-advance mode. Never enable both production time paths.

While the combat SceneTree is paused, `Game._physics_process` is not called, and the pause controller also calls `WorldV2ShipHost.PauseShipWorld()`. Resume reverses both gates. This dual gate is intentional: the engine gate stops Space actors; the Host gate rejects any accidental external Jar step.

## 4. Combat pause integration

`SpaceBattlePauseController` is the only player-facing combat pause authority.

- It is a root-level `CanvasLayer` with `PROCESS_MODE_ALWAYS`.
- Escape toggles pause/resume.
- Window focus loss pauses; focus gain never resumes without player action.
- On pause it pauses the Host first, then sets `SceneTree.paused = true`.
- On resume it releases the SceneTree gate and resumes the Host in the same synchronous call.
- The pause overlay is always-process UI and remains clickable.
- The combat HUD is always-process presentation. Its display polling/toasts may continue, but no gameplay state advances because actors, the Game physics owner, and the Host are paused.
- Leaving the combat scene must clear the SceneTree pause gate so a subsequent menu/game-over scene cannot inherit a paused tree.

Combat spawn staggering, wave-break delays, and the death transition delay are gameplay timers and therefore use `create_timer(seconds, false)`.

## 5. Node ownership and intended scene tree

The current combat scene is deliberately small. Its responsibility boundaries are:

```text
/root
├── GameState (autoload)
│   └── persistent wallet + transient score/wave/segment checkpoint
├── IndustrialRuntime (autoload)
│   └── independent industrial wall-clock/tick policy
├── WorldV2ShipHost (autoload, C#)
│   └── WorldV2Runtime (owned per active ship-world)
│       └── Jar Core bridge session
└── Game (combat scene root, pausable)
    ├── Background (presentation)
    ├── Arena (gameplay world)
    │   ├── StaticBody2D (arena boundaries)
    │   ├── Player (actor + StatusEffectManager)
    │   ├── Enemy actors
    │   ├── Projectile actors
    │   ├── Pickups
    │   └── Asteroids
    ├── Camera2D (presentation, follows gameplay state)
    ├── Hud (CanvasLayer, always-process presentation)
    ├── Spawner (gameplay scheduling, pausable)
    └── PauseController (CanvasLayer, always-process pause authority)
```

Ownership rules:

- `Game` is the combat composition root and the sole Space simulation-step coordinator. It wires already-created domain owners; it must not duplicate Jar rules.
- `Arena` owns transient physical actors. Actors must not become autoloads.
- `Spawner` owns spawn/wave scheduling and its RNG stream, not the game clock or persistent progression.
- `Hud` reads state and sends player intent; it does not advance gameplay.
- `PauseController` owns only pause interaction and the engine/Host pause gates.
- `WorldV2ShipHost` owns one active Jar Runtime lifetime. It is not a second autonomous clock.
- `GameState` owns player wallet and transient run progression values, not the combat scene graph.
- `IndustrialRuntime` owns industrial simulation policy and its own user/focus pause state. Industrial pause is not a request to pause the entire SceneTree.

## 6. Industrial simulation is a separate clock domain

The legacy `IndustrialRuntime` intentionally has its own `running`, `user_paused`, `freeze_when_unfocused`, wall-clock accumulator, backlog cap, and explicit tick API. Its focus freeze drops no elapsed time into the accumulator; its user pause calls the Core bridge pause/resume API. This is not interchangeable with combat's SceneTree pause. The current combat pause is tree-wide, so a pausable IndustrialRuntime autoload is also engine-suspended while that pause is active; its own running/user-paused state is preserved and resumes under its own policy when the tree unpauses.

When the Industrial UI is open, the application flow must decide whether the combat scene exists at all. Do not leave an active combat scene behind the industrial scene and assume that hiding it pauses it. Scene replacement/removal is the preferred ownership boundary until an explicit multi-scene simulation coordinator is introduced.

## 7. Checkpoint and transition rules

- Freeze the battle loadout before instantiating/attaching the combat scene.
- Restore Jar, Space clock remainder, parser/pickup RNG, effect instances, dispatcher receipts, and transient run state before the first simulation step.
- A resumed battle passes through `RESUMING → RESUME_READY → RUNNING`. The restored Host is paused and the SceneTree gate is closed before the ready overlay is shown. Only the explicit Resume action changes `RESUME_READY` to `RUNNING`; restoration itself never authorizes a simulation step.
- Capture the coordinated runtime checkpoint only at a completed Space/Jar step boundary.
- A pause state is a runtime gate and pause reason, not part of the authoritative Jar/Space resource checkpoint. Save the fact that a run is resumable; require an explicit resume action after restoration.
- On terminal exit, dispose the Host-owned Jar session and clear the SceneTree pause gate. Do not leave a stale Host active behind another screen.
- All Game-owned terminal paths converge on one idempotent shutdown method: player death ends; parser/ingress/Host/restore failures fault; unexpected removal of a still-live combat scene faults. Host disposal and SceneTree unpause occur before any transition. Runtime faults are shown in an always-process fault panel with the latched reason and a Main Menu action; they are not reported as player death or routed through GameOver.
- PauseController teardown only releases the engine-wide pause latch. It never resumes the Host merely because its UI node is leaving the tree; the owning Game teardown disposes that Host session.

## 8. Current implementation audit and known migration work

Implemented in this phase:

- Added `SpaceBattlePauseController` to the combat scene. Escape pauses/resumes; focus loss pauses without auto-resume.
- Pause controller calls the Host's pause/resume lifecycle methods as well as the SceneTree gate.
- HUD presentation continues while paused.
- Combat wave spawn, wave-break, death-transition, and explosion-lifetime timers now opt out of process-while-paused behavior.
- The Industrial screen's restart-confirmation countdown also explicitly respects SceneTree pause; the isolated World V2 Core clock probe explicitly keeps its test timers running so it can verify Jar's internal pause independently of Godot pause.
- Source review of Asteroid, enemy, player, projectile, pickup, and player-feature scenes found no explicit process-mode overrides. They inherit the pausable combat root. The BuffPickup lifetime Timer and DoubleShot second-shot Timer also inherit that policy; the pause menu and HUD are the deliberate always-process exceptions.
- Combat scene teardown clears the SceneTree pause gate.
- Production Host already constructs its Runtime with `AutoAdvance = false`, and its own HostState gate rejects advances unless Active.

Still requiring a later systematic migration/audit:

- Every actor, projectile, pickup, effect, and animation scene must be checked for explicit process modes, timers, and callbacks that intentionally bypass pause.
- `GameFlow` is now the sole application scene-navigation owner. Screen owners request a target screen and path; it validates the lifecycle transition, calls `change_scene_to_file`, and restores the prior registry snapshot if Godot rejects the request immediately. The bootstrap route, Menu, Industrial exit, GameOver retry/menu, and combat death route use this API. Hangar's embedded combat launcher enters the same battle lifecycle before attaching its preconfigured scene.
- Resumed battles now enter `RESUME_READY`: the Host and SceneTree are paused before the ready overlay is exposed, and only the explicit Resume action authorizes `RUNNING`.
- Industrial UI focus, application-level pause, and save/exit behavior need a unified policy without collapsing the separate IndustrialRuntime clock.
- `SpaceBattlePauseControllerProbe` is executed by the cross-repository CI workflow. It checks the synchronous SceneTree pause/overlay/resume contract, the `RESUMING → RESUME_READY → RUNNING` state contract, fault presentation/reason retention, duplicate launch rejection, and the real fault-to-main-menu action. The probe's terminal menu transition is verified in headless Godot; window focus behavior, gameplay timer freezing, scene-load rejection, shutdown idempotence, and no post-exit pause leakage still need dedicated automated coverage and GUI acceptance.

## 9. Non-goals

- `SceneTree.paused` is tree-wide, not scoped to the combat subtree: autoloads using an inherited/pausable process mode are also suspended. The current application does not run an independent background simulation behind the combat screen. If that product requirement changes, the background owner must explicitly use an always-process mode and enforce its own independent pause/visibility policy; do not silently rely on scene visibility.
- Do not set `Engine.time_scale = 0` as a substitute for `SceneTree.paused`.
- Do not use Jar logical speed ratio to pause Space actors.
- Do not allow UI visibility, node visibility, or scene-tree presence to become a time authority.
- Do not add arbitrary `PROCESS_MODE_ALWAYS` to gameplay nodes to "fix" a timer; fix the owner and timer policy instead.
- Do not let a UI component own World V2 Runtime lifecycle or Jar commands.


## 10. Central state registry

`GameFlow` is registered as an autoload and is the authoritative registry for application screen and battle lifecycle state. It exposes a version 5 snapshot and `state_changed` signal; version 3 added the externally observable `RESUME_READY` phase, version 4 added the latched fault reason, and version 5 adds the last successfully completed world/logical millisecond positions. Current tracked values are:

- Screen: `MENU`, `HANGAR`, `INDUSTRIAL`, `BATTLE`, `GAME_OVER`.
- Battle phase: `INACTIVE`, `PREPARING`, `RUNNING`, `PAUSED`, `RESUMING`, `RESUME_READY`, `ENDED`, `FAULTED`.
- Pause reason: `NONE`, `PLAYER`, `WINDOW_FOCUS_LOST`, `SYSTEM`.
- Monotonic transition sequence for diagnostics.
- Fault reason and last successfully completed `worldTimeMilli` / `logicalTimeMilli`; failed in-flight steps never overwrite the previous completed position.

MainMenu, Game, IndustrialMain, GameOver, bootstrap, and the combat pause controller publish lifecycle transitions through GameFlow. GameFlow owns root scene replacement; the Hangar launcher owns only the preconfigured embedded-combat attachment. `begin_battle_preparation()` is idempotent only during PREPARING and rejects duplicate launches while RUNNING, PAUSED, or restoring.


## 11. Centralized scene navigation and restore gate

`GameFlow.request_scene_transition(screen, path)` is the only production entry to `SceneTree.change_scene_to_file`. It validates the requested screen against the battle lifecycle, publishes the intended state, requests the Godot transition, and rolls the registry back if Godot returns an immediate error. A later asynchronous scene initialization failure is a different failure boundary: the entering scene must latch `FAULTED` and keep its simulation disabled rather than pretending that the previous scene was restored.

The Hangar's combat scene is attached as a configured child rather than replacing the root scene. Its launcher therefore uses the same `begin_battle_preparation()` lifecycle gate before attachment; it does not call `change_scene_to_file`. The distinction is explicit: GameFlow owns application screen replacement, while the Hangar launcher owns one prevalidated embedded combat attachment.

For checkpoint restoration, `Game._ready()` performs all synchronous restoration and starts the Host, then immediately transitions to `RESUME_READY` and asks the always-process pause controller to pause the Host and SceneTree before the first frame can advance. The overlay remains visible until the player explicitly confirms Resume. The ready state is observable in the versioned GameFlow snapshot and is not conflated with an ordinary player pause.

### Unified battle checkpoint consistency boundary

Schema-v3 SpaceBattleEffectStateStore snapshots are now validated as one cross-domain transaction, not merely as individually well-typed dictionaries:

- The dispatcher state must use its supported schema and repeat the exact frozen ship/loadout identity stored at the snapshot root.
- A non-empty processed-event ledger must carry one Jar world-instance identity. Every event ID must use that world identity and canonical positive demand/cycle sequence values.
- The StatusEffectManager processedOrderEventIds set must exactly equal the dispatcher's processedEventIds set. Duplicate, missing, extra, malformed, or cross-world event identities reject the entire save/load candidate.
- Game.configure_battle_loadout_from_checkpoint repeats the effect/dispatcher identity and event-ledger checks before accepting a caller-supplied snapshot, so callers cannot bypass the file Store by constructing a Dictionary manually.
- This preserves the intended outbox handoff: Space writes the effect state, next dispatcher state, and a Jar checkpoint that may still contain the event in its outbox as one replaceable snapshot; only after the durable write succeeds does the live dispatcher acknowledge the Jar event. If a crash occurs before acknowledgement, restore sees the already-processed event and acknowledges it without reapplying the effect.

SpaceBattleEffectStateStoreProbe now covers mismatched event ledgers, wrong frozen-loadout identity, and non-canonical Jar event IDs in addition to incomplete runtime state. The probe is committed but has not been executed in Godot.
