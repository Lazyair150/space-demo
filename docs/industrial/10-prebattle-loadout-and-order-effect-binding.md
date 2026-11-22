# World V2 × Space — pre-battle skill loadout and order-effect binding

Status: skill-domain architecture plus initial loadout, event dispatch, versioned effect catalog, Buff snapshot, and single-snapshot persistence foundations. Hangar integration and production battle save/load remain incomplete.

## 1. Skills are the player-facing capability model

An Order is the Jar execution blueprint for an equipped **Skill**. The player sees and equips skills from a Space-owned Skill Catalog; Jar does not own skill meaning, reward semantics, combat effects, or UI language.

A skill definition is versioned and separates these concerns:

- **Benefit/effect**: Space-owned effect definition, exact version, parameters, target policy, duration, stacking/refresh behavior, and any tick behavior.
- **Cost**: a Jar order specification: required jar shapes/counts and other supported resource requirements. This is the actual execution cost, not a second manually maintained cost number.
- **Cooldown**: Jar order cooldown controls when the skill can execute again. It is distinct from an effect's active duration in Space.
- **Activation control**: player-manual or automatic policy. This decides who requests execution, not how Jar consumes resources.
- **Loadout area**: Active or Passive. Active skills are placed in the player's manual-control region; Passive skills are placed in the automatic/AI-controlled region. The region is an equipment/control assignment, not a different Jar order type.

Active and Passive are not synonyms for one-shot and continuous effects. A passive skill may execute discrete Jar cycles when its trigger policy is satisfied; an active skill may apply a timed Buff. A skill's trigger policy must not bypass Jar feasibility, resource consumption, or cooldown.

## 2. Battle resource loop

Combat pickups (including energy stones) are acquired by the ship during the battle. Space converts those pickups through the selected production device into Jar-compatible resources. Jar then executes equipped skills using the resource/cost contract materialized from the frozen loadout. A skill only produces its Space benefit after a successful Jar cycle event.

The conceptual loop is:

1. Player equips skills and assigns Active/Passive control areas before battle.
2. Ship fights and acquires resources.
3. Production devices process those resources into Jar resources.
4. Manual input or passive trigger policy requests a skill execution.
5. Jar checks requirements, reserves/consumes resources, executes the order, and enforces its cooldown.
6. On successful completion, Space resolves the exact versioned skill effect and applies its benefit.
7. Effect duration/ticks and Jar cooldown both advance only with Space simulation time.

The player's build decides which capabilities are available and which are automated. It does not remove the player's agency: Active skills remain under direct control; Passive skills delegate trigger decisions to the configured automation policy.

## 3. Build is a single player-authored composition

Before entering combat, the player configures four connected dimensions:

1. Ship selection.
2. Production-device selection.
3. Workshop-combination selection.
4. Order selection.

These are not four unrelated menus. They form one immutable battle build. A ship may constrain compatible devices/workshops/orders; devices determine which Jar shapes can be produced efficiently from battle pickups; workshop combinations determine the processing/reshaping capabilities available to orders; selected orders determine the capabilities/effects the ship can trigger.

The exact compatibility matrix and balance values remain game-design data. The integration must not hardcode one default combination as the universal build.

## 4. Immutable battle loadout

At the transition from hangar/preparation into combat, create a versioned immutable loadout snapshot. Suggested top-level fields:

- shipWorldId: unique identity for this combat ship-world instance;
- loadoutId and loadoutVersion;
- shipDefinitionId and shipDefinitionVersion;
- productionDeviceSelections;
- workshopCombinationSelection;
- selectedOrderBindings;
- configuration/catalog fingerprints required to reconstruct the battle.

Each selected order binding contains two separate contracts:

### Jar order materialization

- orderDefinitionKey: stable opaque identity for the selected order blueprint/slot;
- Jar order specification (type and requirements);
- order cooldown duration;
- selected demand area/policy where the game configuration requires it.

Jar receives only the domain data needed to create and execute the order. It does not receive Space BuffDefinition objects or scripts.

### Space effect binding

- effectDefinitionId;
- effectDefinitionVersion;
- effect parameters owned by Space;
- target/recipient policy owned by Space.

The effect binding is immutable for the battle. The same orderDefinitionKey must resolve to the same effect definition/version throughout that ship-world, even if global catalog data is updated later.

## 5. Runtime ownership and construction

The stable WorldV2ShipHost remains the owner of the one Jar session for the active ship-world.

The host must be initialized from the committed battle loadout, not from a global sandbox file:
1. Hangar validates the full build and compatibility constraints.
2. Space freezes a loadout snapshot and assigns shipWorldId.
3. The host creates World V2 using the selected production/workshop/order configuration.
4. Jar demand creation receives the stable orderDefinitionKey alongside its Jar requirements and cooldown.
5. Space retains the same immutable orderDefinitionKey -> effect binding table for event dispatch.
6. Combat starts only after both the Jar world and Space effect runtime have accepted the same loadout identity/version.

If Jar world construction fails, the battle build must not silently fall back to the sandbox or a partial configuration.

## 6. Energy-stone production path

Energy stones are Space-world pickups. Each stone has a type/property corresponding to a Jar shape. The universal processor accepts all types and contributes the stone's production value to the matching shape's progress. Progress is independent per shape; when a shape reaches one complete unit, the production path emits a Jar of that shape. Different production devices have different per-shape processing rates.

This is not the same as the current World V2 time-based Producer rate model. Do not reinterpret a static producer rate as energy-stone ingestion. The new path needs explicit concepts:
- typed stone input and pickup identity;
- processor/device definition and per-shape rate;
- per-shape fractional progress;
- output Jar creation and destination;
- accepted/remainder receipt and idempotent pickup processing;
- checkpoint/save state for accumulated progress and pending input.

The exact numeric conversion formula and partial-input handling are configuration decisions; the architecture must preserve per-shape progress independently and avoid losing unprocessed Space-owned stones.

## 7. Workshop configuration

The selected workshop combination materializes the Jar workshop roster and its constraints:
- fixed Master/Slave roles;
- available spare workshops;
- shape marks, additional marks, bans, jar/liquid capacities;
- selected initial master/slave identities;
- existing World V2 replacement rules during combat.

Do not confuse pre-battle workshop-combination selection with in-battle workshop replacement. The former constructs the initial roster; the latter is a timed domain operation on the already-created roster.

## 8. Skill effect dispatch

When Jar reports a durable successful order-cycle event:
1. Space validates shipWorldId, loadoutId/version, orderDefinitionKey, and eventId.
2. Space resolves the immutable effect binding captured for this battle.
3. Space resolves the referenced BuffDefinition or other effect definition.
4. Space applies it through the existing Space effect system (for buffs, StatusEffectManager), using the effect's own duration/stacking/target policy.
5. Space persists the processed event identity and resulting effect state.
6. Space acknowledges the Jar event only after its effect state is durable.

Jar order cooldown and Space buff duration are distinct. Both use the shared simulation clock, but they have different owners and meanings.

The current BuffDefinition/StatusEffectManager is a reusable effect executor. Buff definitions now carry an explicit positive definition_version; a SpaceEffectCatalog resolves the exact (id, version), never silently substituting the latest version. Buff runtime snapshots include definition identity/version, target key, remaining duration, stacks, tick count/accumulator, and an extension hook for subclass state. Restore stages and validates all instances before replacing the live set and rebuilds stat modifiers without calling on_apply again. The manager also records processed order event IDs in its runtime snapshot so an in-process retry cannot add stacks twice. The new integration should bind orders to that system rather than create a second Buff implementation. The old BuffPickup remains a separate world pickup trigger; an order event must not be faked as a pickup collision.

The branch now contains:
- `SpaceBattleLoadoutSnapshot.gd`: validates and deep-copies the four-dimension battle build, including a fully materialized `jarWorldOptions` object, selected-order Jar data, versioned Space effect bindings, and a stable loadout fingerprint;
- `SpaceOrderEffectDispatcher.gd`: reads detached Jar events, resolves only bindings present in the frozen loadout, and delegates effect application plus durable effect/processed-ID persistence to an injected commit callback. It acknowledges Jar only after that callback reports a durable commit;
- `WorldV2RuntimeNode` and `WorldV2ShipHost`: expose pending event reads and acknowledgments to GDScript; demand snapshots also expose orderDefinitionKey and cycleSequence.
- `WorldV2RuntimeNode.InitializeWorldFromJson` and `WorldV2ShipHost.BeginShipWorldFromJson`: provide a no-sandbox-fallback construction path for a frozen loadout-derived Jar configuration.
- `WorldV2RuntimeNode.AddJarDemand` and `WorldV2ShipHost.MaterializeSelectedOrders`: materialize all selected Jar demands before the first Space simulation step. A partial failure disposes the not-yet-started ship world; demand creation is not allowed after time begins.
- `Game.gd`: accepts a frozen loadout and a durable effect-commit callback before entering the SceneTree; starts the Jar world from loadout JSON, materializes selected orders, then drains pending events after each Jar advance. Sandbox startup remains an explicit development-only fallback.

The dispatcher is an integration boundary, not yet a complete live combat feature: no Hangar currently constructs the snapshot, and no concrete durable commit callback/save implementation is wired. If a loadout selects orders without a valid callback, Game.gd fails closed and does not enter combat.

## 9. Shared time

The active Space simulation step is the sole clock source for:
- ship/world actors;
- Jar production and order execution/cooldown;
- active BuffInstance duration and tick effects;
- other combat timers that belong to the same simulation.

No subsystem in this list may use its own wall-clock catch-up. Pause freezes all of them; resume continues from their preserved state.

## 10. Current implementation gap

The branch currently has:
- WorldV2ShipHost with external time ingress, but it loads world_v2_sandbox.json;
- combat physics forwarding to Jar;
- StatusEffectManager external-time mode, advanced by the same combat physics delta;
- existing BuffDefinition and BuffInstance execution.

It does not yet have:
- hangar/pre-battle loadout data and UI;
- loadout-to-WorldV2Options materialization;
- energy-stone processor ingestion/progress in the new Jar world;
- Hangar/pre-battle UI and construction of the immutable snapshot from actual ship/device/workshop/order catalog selections;
- binding the selected orders' orderDefinitionKey values to the actual Jar demand creation calls;
- production-grade battle save/load orchestration and platform-tested durable replacement semantics for the combined effect/dispatcher snapshot;
- restoring the dispatcher and effect state during battle save/load;
- making the frozen-loadout path the normal Hangar-to-combat path and disabling the sandbox development fallback in production.

Implement in that dependency order. Do not wire an order to a BuffDefinition until the Jar event identity and durable delivery contract exist.
