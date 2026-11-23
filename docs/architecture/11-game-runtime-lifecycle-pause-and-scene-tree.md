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
- `FAULTED`: a runtime fault has latched; no further simulation step is accepted.

A pause reason is metadata, not another running state: `PLAYER`, `WINDOW_FOCUS_LOST`, or a future explicit system reason. Losing focus pauses automatically; regaining focus does not automatically resume. The player must explicitly resume.

## 2. What Godot pause actually freezes

The authoritative in-scene gate is `SceneTree.paused`.

- Nodes with `PROCESS_MODE_PAUSABLE` (or `INHERIT` under a pausable parent) stop their idle, physics, and input processing while the tree is paused.
- `PROCESS_MODE_ALWAYS` continues processing. Reserve it for pause controls and UI that must remain interactive.
- `PROCESS_MODE_WHEN_PAUSED` is for narrowly scoped paused-only UI/diagnostics.
- `PROCESS_MODE_DISABLED` stops processing regardless of tree pause.
- Physics simulation and collision callbacks for the paused gameplay tree stop with the tree pause.
- A `Timer` node must inherit the gameplay pause policy. Do not enable its process-while-paused behavior for combat scheduling.
- `SceneTree.create_timer(seconds)` defaults to processing while paused. Combat delays must explicitly use `create_timer(seconds, false)`. A UI-only animation may deliberately use an always-processing timer, but it must be owned by UI and documented.
- Tweens/AnimationPlayers attached to gameplay nodes inherit their owner process policy. Pause-menu animation is UI-owned and may continue.
- Audio pause/fade policy must be explicit per bus/player; do not infer it from physics pause.

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
- A resumed battle should enter a paused/ready-to-resume presentation state in the eventual flow controller; it must not silently advance while a restore screen is visible.
- Capture the coordinated runtime checkpoint only at a completed Space/Jar step boundary.
- A pause state is a runtime gate and pause reason, not part of the authoritative Jar/Space resource checkpoint. Save the fact that a run is resumable; require an explicit resume action after restoration.
- On terminal exit, dispose the Host-owned Jar session and clear the SceneTree pause gate. Do not leave a stale Host active behind another screen.

## 8. Current implementation audit and known migration work

Implemented in this phase:

- Added `SpaceBattlePauseController` to the combat scene. Escape pauses/resumes; focus loss pauses without auto-resume.
- Pause controller calls the Host's pause/resume lifecycle methods as well as the SceneTree gate.
- HUD presentation continues while paused.
- Combat wave spawn, wave-break, and death-transition timers now opt out of process-while-paused behavior.
- Combat scene teardown clears the SceneTree pause gate.
- Production Host already constructs its Runtime with `AutoAdvance = false`, and its own HostState gate rejects advances unless Active.

Still requiring a later systematic migration/audit:

- Every actor, projectile, pickup, effect, and animation scene must be checked for explicit process modes, timers, and callbacks that intentionally bypass pause.
- MainMenu/Hangar/Industrial/GameOver navigation should eventually be driven by one application-flow coordinator, not unrelated direct scene changes.
- The resumed-battle launch path should show a paused restore-ready state before authorizing simulation.
- Industrial UI focus, application-level pause, and save/exit behavior need a unified policy without collapsing the separate IndustrialRuntime clock.
- `SpaceBattlePauseControllerProbe` now checks the synchronous SceneTree pause/overlay/resume contract, but has not been executed. Add automated Godot probes for focus-loss behavior, gameplay timer freezing, Host lifecycle state, and no post-exit pause leakage.

## 9. Non-goals

- `SceneTree.paused` is tree-wide, not scoped to the combat subtree: autoloads using an inherited/pausable process mode are also suspended. The current application does not run an independent background simulation behind the combat screen. If that product requirement changes, the background owner must explicitly use an always-process mode and enforce its own independent pause/visibility policy; do not silently rely on scene visibility.
- Do not set `Engine.time_scale = 0` as a substitute for `SceneTree.paused`.
- Do not use Jar logical speed ratio to pause Space actors.
- Do not allow UI visibility, node visibility, or scene-tree presence to become a time authority.
- Do not add arbitrary `PROCESS_MODE_ALWAYS` to gameplay nodes to "fix" a timer; fix the owner and timer policy instead.
- Do not let a UI component own World V2 Runtime lifecycle or Jar commands.
