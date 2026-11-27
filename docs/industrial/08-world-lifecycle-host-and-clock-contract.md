# World V2 × Space — world host and simulation clock contract

Status (2026-11-25): the World V2 host/clock and lifecycle integration have been built and exercised by the cross-repository workflow at Space commit `74a93ed281d94823608b0c6803edd78dd9f068cc` against Core `b342259fe04363386085dc9a4ca995112954ed43` (run `45438436612`, success). The Space PR later advanced through the HUD probe type-annotation change and subsequent documentation-status cleanup. The exact current branch head is tracked in `docs/execution/2026-11-24-cross-repo-integration.txt`; no successful workflow is recorded for the post-cleanup documentation head, so exact-latest-head verification remains pending. Older implementation-status paragraphs below are chronological checkpoints, not current validation claims.

## 1. Repository facts verified

- `project.godot` registers `GameState`, `GameFlow`, and `WorldV2ShipHost`. The legacy `IndustrialRuntime` autoload has been removed.
- `Game.tscn` is the active combat scene. `Game.gd` currently uses `_physics_process(delta)` only for camera shake; it does not own a general simulation clock.
- Player movement, firing cooldown, enemy movement, and other combat actors use physics processing and the supplied physics `delta`.
- `main_menu.gd` routes Start into `SpaceHangar.tscn`. The Hangar constructs a frozen loadout and calls `SpaceHangarBattleLauncher.launch_new_battle` before attaching the combat scene; the sandbox path remains an explicit development fallback.
- The legacy IndustrialRuntime, JarCoreBridge, IndustrialMain scene, old industrial panels, sandbox/tradeoff data, and legacy industrial test harness have been deleted. No legacy tick loop remains in the project.
- `WorldV2RuntimeNode` owns and disposes its Bridge session. Its `_ExitTree` is terminal. Therefore it must not be parented beneath a replaceable UI scene.
- `WorldV2RuntimeNode.AdvanceWorldTime(long)` is the explicit external-time entry point. Production use must set `AutoAdvance = false`.

## 2. Ownership model

The production ownership chain is:

```
Space application
  └─ SpaceWorldHost (stable world-lifecycle owner)
       ├─ WorldV2RuntimeNode (one Jar session for this ship-world instance)
       └─ presentation consumers (may attach/detach independently)
```

The host is not the UI and is not a second simulation. It owns lifecycle and forwards authorized time; World V2 remains the sole owner of Jar domain state and rules.

A production host must be stable across presentation changes. Closing, hiding, replacing, or reopening the Jar interface must not recreate or dispose the Jar session. The host/session is disposed only when the owning Space ship-world is actually unloaded or terminated. If a future save/load flow requires suspension rather than disposal, that is an explicit host lifecycle transition and must preserve a defined checkpoint; it must not be implemented by leaving a ticking node alive behind the menu.

## 3. Lifecycle state machine

Host lifecycle states:

- `Absent`: no ship-world owns a Jar session.
- `Created`: the owning ship-world exists and the Jar runtime has been created, but simulation is not yet authorized to advance.
- `Active`: the Space world is actively simulating; positive simulation deltas may be forwarded.
- `Paused`: the owning world remains loaded but its simulation is stopped; no positive delta is forwarded.
- `Suspended`: a higher-level transition temporarily suspends the owning world; no delta is forwarded and no wall-clock catch-up is allowed.
- `Disposed`: the ship-world ended and the owned Jar runtime was disposed. Terminal for that host instance.
- `Faulted`: Jar host/runtime faulted; no further Jar advancement or mutations are forwarded until an explicit recovery/new-world policy is executed.

Allowed transitions:

```
Absent -> Created -> Active <-> Paused
                         |        |
                         v        v
                      Suspended <-+
                         |
             resume -----+-----> Active
                         |
                         v
                      Disposed

Created/Active/Paused/Suspended -> Faulted
Faulted -> Disposed
```

Rules:
- A new ship-world instance creates one new host/session. Duplicate initialization for the same instance is rejected.
- Combat pause and game pause map to `Paused`; return-to-menu/world unload maps to `Suspended` followed by `Disposed` unless a separately specified checkpoint-preserving transition is used.
- Scene/UI visibility is not a lifecycle state.
- A Jar runtime fault is contained and reported to Space. Jar does not pause, resume, or otherwise control the Space world.
- Disposed is terminal. A new world gets a new host/session; do not silently reinitialize a disposed RuntimeNode.

## 4. Clock authority and exactly-once forwarding

Space is the only simulation-time authority. The integration point must be a callback in the actual owning Space simulation loop, not the Jar UI, not an always-running autoload `_Process`, and not a wall-clock timer.

For every simulation step that the owning Space world actually executes:

1. Space obtains the simulation delta supplied to that step.
2. The host verifies lifecycle state is `Active`.
3. The host converts seconds to integer milliseconds using a retained fractional-millisecond remainder.
4. The host calls `WorldV2RuntimeNode.AdvanceWorldTime(wholeMilliseconds)` at most once for that step.
5. If the converted integer is zero, it makes no call and retains the fractional remainder.
6. If the call faults, the host latches the fault and does not forward later steps.

No Space simulation step means no Jar advancement. In particular:
- combat/game pause: no physics simulation step, therefore no Jar delta;
- menu or unloaded world: no owning-world callback, therefore no Jar delta;
- Jar UI hidden while the Space world remains active: Space still calls the host, therefore Jar continues;
- process stalls, window focus changes, and wall-clock elapsed time never create catch-up delta.

The host must not independently subscribe to a second frame/physics callback while the owning world also forwards time. Exactly one integration route is allowed.

## 5. Time scale and Jar speed ratio

The Space-provided delta is the already-authorized simulation delta for the current world step. If Godot's owning simulation loop has already applied the game's time scale, the host must not multiply by that scale again.

To preserve the settled semantic that Jar is an internal ship system sharing the Space world's time, the production Jar speed ratio should be fixed at 1x. Space slow motion/fast motion is reflected in the simulation delta supplied by Space. A second independent Jar speed ratio would make Jar time diverge from the ship/world and should not be exposed as an ordinary player control. The Core API may retain its ratio capability for isolated probes or other hosts, but production integration must not apply a second time multiplier.

The host must never derive Jar time from `Time.get_ticks_msec()`, wall-clock timers, process uptime, or elapsed time since the UI was opened.

## 6. UI and scene transitions

The legacy `IndustrialMain.tscn` has been removed. The Jar interface is now designed as a presentation of the active ship-world, not a standalone production scene.

The eventual player-facing integration should make the Jar interface a presentation layer attached to the active ship-world (overlay, subview, or other UI composition), not the owner of the Jar runtime. The exact visual transition and whether opening the interface pauses combat remain gameplay/presentation decisions. Regardless of that decision, presentation visibility must not itself be the clock authority.

The legacy industrial shortcut has been removed. The production Start route now enters the Hangar, which supplies the authored frozen loadout and launch dependencies; direct sandbox startup remains development-only.

## 7. Boundary rules for future resource and result adapters

- Space owns pickup/drop/world resources. Jar owns its ship liquid inventory, jars, workshops, demands, execution, and Jar ledger.
- Resource import must be an explicit command with a stable operation identity and a reported accepted/rejected/discarded result. Never mutate Jar's internal dictionaries directly from Space.
- Resource export must likewise be an explicit Jar domain result; Space decides whether and how to convert it into a game resource.
- Order completion is a Jar domain fact, not a reward instruction. Any mission, equipment, score, currency, or combat consequence is Space policy and must be idempotent on a stable completion identity.
- No legacy wallet, ore, material, attack-upgrade, enemy-damage, or reward behavior is implicitly migrated.
- Capacity and conversion rules remain undecided until the resource mapping is approved. The adapters must preserve partial acceptance/rejection information rather than silently clamp.

## 8. Implementation sequence

1. Introduce a stable Space-world host with explicit `Create/Activate/Pause/Suspend/Dispose` operations and a single external-time forwarding method.
2. Create the World V2 RuntimeNode under that host with `AutoAdvance = false`; connect fault/snapshot signals once.
3. Add exactly one call from the owning Space simulation step. Do not put the call in the Jar UI.
4. Make the Jar UI consume host snapshots and send only documented World V2 commands.
5. (Completed) Remove the old full-scene industrial entry; the production Hangar must attach to the owning ship-world lifecycle.
6. Implement explicit resource import/export and completion event adapters after their domain semantics are approved.
7. (Completed) Retire the legacy industrial autoload and old wallet/reward coupling. No legacy rewards or attack upgrades are migrated.

## 9. Explicitly unresolved

- Whether opening the Jar interface pauses combat or leaves combat running behind an overlay.
- Whether Jar completion has any mission/progression/equipment meaning in Space.
- Which Space pickups/resources can be imported, at what conversion ratio, and with what capacity policy.
- Save identity, checkpoint versioning, and whether menu suspension preserves an in-progress Jar execution.


## 10. First production-host implementation status

The first host slice is now present in this branch:

- `WorldV2ShipHost.cs` is registered as the `WorldV2ShipHost` autoload. It owns a child `WorldV2RuntimeNode`, sets `AutoAdvance = false` before the child enters the tree, and exposes explicit begin/pause/resume/suspend/end operations.
- `Game.gd` begins the Jar session when the combat ship-world scene enters, forwards the scene's `_physics_process(delta)` to `AdvanceSpaceSimulation(delta)` once per physics callback, and ends the Jar session when that owning scene exits.
- The host retains fractional milliseconds, forwards only whole milliseconds, and never runs its own process loop.
- The host latches Jar faults and stops forwarding. It does not stop or control the Space simulation.
- The current game has no explicit pause-menu API in the audited path. If a future pause sets the SceneTree paused, the normal pausable physics callback stops; any custom pause implementation must also call the host pause/resume operations or otherwise guarantee that no simulation callback reaches it.
- The first wiring uses the existing World V2 sandbox config and creates a fresh Jar session per combat-scene lifetime. This is an integration slice, not the final ship save/load or player-facing Jar UI.

This implementation has not yet been locally compiled or run in Godot in this turn. It must not be described as validated. The next code pass should add a focused host lifecycle/clock probe and compile-level checks, then move to explicit resource import/export contracts.


## 11. Shared clock now includes the existing Space buff manager

The existing Space Buff system was audited:
- StatusEffectManager previously advanced BuffInstance duration from its own _process(delta).
- That was a second time ingress, distinct from the combat world's _physics_process(delta) used by actors and the Jar host.
- StatusEffectManager now has an explicit external_time_authority mode and advance_from_space_world(delta) entry point.
- The combat scene enables external authority and advances already-active buffs from the same physics delta used by Jar. Its independent _process path is disabled in this mode.
- Buffs already active at the start of a physics step consume that step's delta. A future Jar completion event applied at the end of the step will begin consuming duration on the next step, avoiding immediate loss of one whole frame's duration.

This closes the known dual-clock path for combat Buff durations. Jar's phase 4.10c branch now implements the successful-cycle outbox; Space consumes its detached events through the host boundary described below. No concrete order-to-BuffDefinition numerical mapping is implied yet.

## 12. Current integration boundary status

Implemented on the current Space branch:
- Jar PR #28 provides opaque orderDefinitionKey, persisted cycleSequence, OrderCycleCompleted outbox events, checkpoint persistence, and ApplicationService/Bridge read/ack operations.
- WorldV2RuntimeNode and WorldV2ShipHost expose pending-event reads and acknowledgments to GDScript; demand snapshots expose orderDefinitionKey and cycleSequence.
- SpaceBattleLoadoutSnapshot validates and deep-copies the four pre-battle build dimensions: ship, production devices, workshop combination, and selected orders with versioned effect bindings. It includes the materialized jarWorldOptions object and a deterministic SHA-256 loadout fingerprint.
- WorldV2ShipHost.BeginShipWorldFromJson provides a no-sandbox-fallback construction path. MaterializeSelectedOrders adds selected Jar demands before the first simulation step and disposes the unstarted world if any demand fails.
- SpaceOrderEffectDispatcher validates events against the frozen order bindings, deduplicates by eventId, and requires an injected durable commit callback before acknowledging Jar.
- Game.gd supports pre-tree loadout/callback configuration and drains events after advancing Jar, so newly emitted effects begin their duration on the next simulation step.

Still incomplete:
- Hangar/pre-battle UI does not yet construct the snapshot from actual catalogs or call the frozen-loadout path. The existing default development route still uses world_v2_sandbox.json.
- No concrete durable effect-commit callback is wired. It must atomically persist Buff/effect state and processed EventIds; until then, selected-order combat startup fails closed.
- Dispatcher/effect state save/restore is not connected to a battle save system.
- Typed energy-stone pickup ingress and shape-specific production-device processing are not yet wired to the World V2 production area.
- The production host/clock, C# loadout materialization path, and GDScript loadout/dispatcher scripts have not yet been locally compiled or run in Godot.


## 13. Skill model and effect-state persistence update

The player-facing concept is a **Skill Catalog**. Each equipped skill is represented on the Jar side by an executable order blueprint plus Space-owned effect binding. The existing loadout `area` field assigns a skill to Active or Passive; a separate activation policy will distinguish manual player requests from passive trigger automation. Neither area nor trigger policy may bypass Jar resource feasibility or cooldown.

New Space foundations on the current branch:
- `BuffDefinition.definition_version` is a positive versioned identity; `SpaceEffectCatalog` resolves exact ID/version pairs.
- `BuffInstance` snapshots preserve target key, remaining duration, stacks, tick count/accumulator, and an extension point for subclass-owned mutable state.
- `StatusEffectManager` snapshots preserve active instances and processed Jar event IDs. Restore stages and validates all entries, then rebuilds stat modifiers without replaying apply/expire gameplay callbacks.
- `SpaceOrderEffectCommitter` resolves the selected effect binding, applies it with runtime EventId idempotency, and saves the effect snapshot together with the dispatcher's proposed processed-ID state.
- `SpaceBattleEffectStateStore` uses a pending snapshot and recoverable previous file. Its replacement/recovery behavior still needs platform validation; it is not claimed to be a cross-platform filesystem transaction.

Not yet implemented: Skill Catalog content/data, actual Active input requests, Passive trigger/automation policy, target-policy catalog data, full battle save/load orchestration, and Hangar construction of the frozen build. The combat sandbox path remains development-only.


## 13. Legacy industrial client retirement (2026-11-23)

The old turn-based industrial client has been removed from the active project:
- Removed the IndustrialRuntime autoload and legacy JarCoreBridge.
- Removed IndustrialMain and its menu shortcut, old industrial panels, old sandbox/tradeoff JSON, old industrial tests, and the outdated 01–06 client documents.
- Removed the old ore/material/attack-upgrade wallet from GameState, the asteroid ore reward, and the HUD's industrial reward/objective prompts. The player weapon now starts from its Space baseline; future permanent weapon profiles belong to the Space ship/skill model.
- Kept WorldV2ShipHost, WorldV2RuntimeNode, the new World V2 probes, SpaceJarHudObserver, and shape presentation code.

This is source retirement, not proof of a successful Godot build. The production Hangar route, typed non-Buff skill executors, durable effect commit wiring, and full runtime validation remain open.
