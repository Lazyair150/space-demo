# World V2 × Space — pre-battle loadout and order-effect binding

Status: architecture contract plus initial loadout/dispatch boundary code. The current combat host still uses a sandbox Jar configuration; hangar UI, loadout materialization, and durable effect commit integration are not yet complete.

## 1. Build is a single player-authored composition

Before entering combat, the player configures four connected dimensions:

1. Ship selection.
2. Production-device selection.
3. Workshop-combination selection.
4. Order selection.

These are not four unrelated menus. They form one immutable battle build. A ship may constrain compatible devices/workshops/orders; devices determine which Jar shapes can be produced efficiently from battle pickups; workshop combinations determine the processing/reshaping capabilities available to orders; selected orders determine the capabilities/effects the ship can trigger.

The exact compatibility matrix and balance values remain game-design data. The integration must not hardcode one default combination as the universal build.

## 2. Immutable battle loadout

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

## 3. Runtime ownership and construction

The stable WorldV2ShipHost remains the owner of the one Jar session for the active ship-world.

The host must be initialized from the committed battle loadout, not from a global sandbox file:
1. Hangar validates the full build and compatibility constraints.
2. Space freezes a loadout snapshot and assigns shipWorldId.
3. The host creates World V2 using the selected production/workshop/order configuration.
4. Jar demand creation receives the stable orderDefinitionKey alongside its Jar requirements and cooldown.
5. Space retains the same immutable orderDefinitionKey -> effect binding table for event dispatch.
6. Combat starts only after both the Jar world and Space effect runtime have accepted the same loadout identity/version.

If Jar world construction fails, the battle build must not silently fall back to the sandbox or a partial configuration.

## 4. Energy-stone production path

Energy stones are Space-world pickups. Each stone has a type/property corresponding to a Jar shape. The universal processor accepts all types and contributes the stone's production value to the matching shape's progress. Progress is independent per shape; when a shape reaches one complete unit, the production path emits a Jar of that shape. Different production devices have different per-shape processing rates.

This is not the same as the current World V2 time-based Producer rate model. Do not reinterpret a static producer rate as energy-stone ingestion. The new path needs explicit concepts:
- typed stone input and pickup identity;
- processor/device definition and per-shape rate;
- per-shape fractional progress;
- output Jar creation and destination;
- accepted/remainder receipt and idempotent pickup processing;
- checkpoint/save state for accumulated progress and pending input.

The exact numeric conversion formula and partial-input handling are configuration decisions; the architecture must preserve per-shape progress independently and avoid losing unprocessed Space-owned stones.

## 5. Workshop configuration

The selected workshop combination materializes the Jar workshop roster and its constraints:
- fixed Master/Slave roles;
- available spare workshops;
- shape marks, additional marks, bans, jar/liquid capacities;
- selected initial master/slave identities;
- existing World V2 replacement rules during combat.

Do not confuse pre-battle workshop-combination selection with in-battle workshop replacement. The former constructs the initial roster; the latter is a timed domain operation on the already-created roster.

## 6. Order effect dispatch

When Jar reports a durable successful order-cycle event:
1. Space validates shipWorldId, loadoutId/version, orderDefinitionKey, and eventId.
2. Space resolves the immutable effect binding captured for this battle.
3. Space resolves the referenced BuffDefinition or other effect definition.
4. Space applies it through the existing Space effect system (for buffs, StatusEffectManager), using the effect's own duration/stacking/target policy.
5. Space persists the processed event identity and resulting effect state.
6. Space acknowledges the Jar event only after its effect state is durable.

Jar order cooldown and Space buff duration are distinct. Both use the shared simulation clock, but they have different owners and meanings.

The current BuffDefinition/StatusEffectManager is a reusable effect executor. The new integration should bind orders to that system rather than create a second Buff implementation. The old BuffPickup remains a separate world pickup trigger; an order event must not be faked as a pickup collision.

The branch now contains:
- `SpaceBattleLoadoutSnapshot.gd`: validates and deep-copies the four-dimension battle build, including selected-order Jar data and versioned Space effect bindings;
- `SpaceOrderEffectDispatcher.gd`: reads detached Jar events, resolves only bindings present in the frozen loadout, and delegates effect application plus durable effect/processed-ID persistence to an injected commit callback. It acknowledges Jar only after that callback reports a durable commit;
- `WorldV2RuntimeNode` and `WorldV2ShipHost`: expose pending event reads and acknowledgments to GDScript; demand snapshots also expose orderDefinitionKey and cycleSequence.

The dispatcher is an integration boundary, not yet a live combat feature: no Hangar currently constructs the snapshot, no durable commit callback is wired, and Game.gd does not yet drain events.

## 7. Shared time

The active Space simulation step is the sole clock source for:
- ship/world actors;
- Jar production and order execution/cooldown;
- active BuffInstance duration and tick effects;
- other combat timers that belong to the same simulation.

No subsystem in this list may use its own wall-clock catch-up. Pause freezes all of them; resume continues from their preserved state.

## 8. Current implementation gap

The branch currently has:
- WorldV2ShipHost with external time ingress, but it loads world_v2_sandbox.json;
- combat physics forwarding to Jar;
- StatusEffectManager external-time mode, advanced by the same combat physics delta;
- existing BuffDefinition and BuffInstance execution.

It does not yet have:
- hangar/pre-battle loadout data and UI;
- loadout-to-WorldV2Options materialization;
- energy-stone processor ingestion/progress in the new Jar world;
- Hangar/pre-battle UI and materialization of the immutable snapshot into WorldV2Options and Jar demand creation;
- binding the selected orders' orderDefinitionKey values to the actual Jar demand creation calls;
- a concrete durable Space effect commit callback that atomically persists Buff/effect state with processed EventIds;
- invoking the dispatcher at the Space physics-step boundary and restoring its state during battle save/load;
- replacing the sandbox configuration with the frozen loadout-derived world configuration.

Implement in that dependency order. Do not wire an order to a BuffDefinition until the Jar event identity and durable delivery contract exist.
