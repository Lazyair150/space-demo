# World V2 × Space — resource, order-effect, and event contract

Status: skill semantics are settled at the domain boundary. Jar orders are execution/cost blueprints for equipped Space skills; Jar owns resource consumption/execution/cooldown, while Space owns skill benefit/effect definitions, versions, targets, stacking, and duration. Concrete catalog content and trigger policies remain implementation/data work.

## 1. Settled gameplay model

Jar is the ship-internal combat-energy system. An order is the Jar execution blueprint for a player-equipped Space skill. The player selects skills from a Skill Catalog; Jar sees only opaque order identity, requirements/cost, area assignment, and cooldown. A skill benefit may be a cooldown buff, combat action, support effect, or other Space-world capability.

The pre-battle build is a player-authored composition of:
1. **Ship selection** — selects the ship and its baseline capabilities/system configuration.
2. **Production-device selection** — determines how collected typed energy stones are processed into shape-specific Jar production progress.
3. **Workshop-combination selection** — determines how available Jars are constrained, reshaped, and routed to satisfy order requirements.
4. **Order selection** — determines which capabilities the ship is configured to produce/execute and which Space world effects successful order cycles invoke.

During combat, Space and Jar share one simulation clock. A pause freezes combat, Jar production, order execution, and order cooldowns together. Jar order cooldown is the skill reuse lockout. Space effect duration is how long an applied benefit remains active. These are independent timers with the same Space simulation-time source.

Intended chain:

\`\`\`
Pre-battle loadout
  ├─ ship
  ├─ production devices
  ├─ workshop combination
  └─ selected orders ──> Space effect bindings
                           |
Combat world begins       |
  |                       |
typed energy-stone drops  |
  v                       |
Jar production -> Jars -> workshop processing
                              |
                         order execution
                              |
                         order cycle succeeds
                              |
                    stable completion fact
                              |
                    Space effect dispatcher
                              |
                  buff / combat / world effect
\`\`\`

Jar must not implement the buff itself, mutate enemies, change player health, or grant legacy wallet/reward values. It reports that the configured order cycle succeeded; Space applies the effect associated with the pre-battle configuration.

## 2. Ownership

| State | Owner |
|---|---|
| Ship selection, production device selection, workshop combination selection, selected order loadout | Space / pre-battle loadout |
| Energy stones in the combat world and their pickup identity | Space |
| Energy-stone processing policy and shape-specific production progress, once configured in Jar | Jar production domain |
| Jar resources, ship liquid inventory, jars, workshops, demands, reservations, execution, and order cooldown | Jar World V2 |
| Order definition -> Space effect binding | Space loadout/effect catalog |
| Successful order-cycle fact | Jar World V2 |
| Buff instances, duration, stacking/refresh rules, cooldown display, combat modifiers, and other world effects | Space combat/effect system |

The Space effect binding must be versioned and captured with the pre-battle loadout. A running battle must not silently change the meaning of an already selected order if the global effect catalog is updated mid-run.

## 3. Order identity and completion mapping

The current Jar order demand has a runtime integer DemandId, an order specification, and its own cooldown duration/remaining time. A persistent demand may remain on the board after successful fulfillment, enter its cooldown, become ready again, and execute another cycle.

Therefore DemandId alone is not a unique completion identity. The same configured order can successfully execute many times in one battle.

The integration contract should distinguish:

- orderDefinitionId: stable opaque identity of the selected order blueprint/loadout slot. Jar stores or transports it without interpreting it.
- demandId: Jar runtime identity of the currently loaded demand.
- cycleSequence: monotonically increasing successful fulfillment number for that demand (or an equivalent persisted unique cycle identity).
- eventId: stable identity derived from ship-world identity + demand identity + cycle sequence, or allocated and persisted atomically by Jar.
- effectDefinitionId and effectDefinitionVersion: Space-owned binding captured in the loadout. These are not interpreted by Jar.

Recommended event payload:
- eventId
- shipWorldId
- jarWorldInstanceId
- orderDefinitionId
- demandId
- cycleSequence
- effectDefinitionId
- effectDefinitionVersion
- completedAtWorldTime
- executionResult / requirement summary
- any Jar-owned output references that Space is explicitly allowed to consume

The event means **one successful order cycle completed**. It does not mean a buff was applied successfully; Space's effect dispatcher owns that result.

### Repeated cycles and cooldown

- Jar owns the order's configured cooldown duration and remaining time.
- On successful fulfillment, Jar's existing demand-area policy determines whether the demand is removed or retained and put on cooldown.
- For retained orders, each successful cycle produces a distinct event ID even though demandId is unchanged.
- The cooldown counts down only while the owning Space simulation advances.
- Space owns the buff's active duration, stacking/refresh policy, target selection, and actual gameplay effect. These must not be conflated with Jar's order cooldown.
- If an order fails, is cancelled, or is interrupted, it must not emit a successful-cycle event. Any separate terminal telemetry is not a buff trigger.

The Jar phase 4.10c branch now accepts opaque orderDefinitionKey values, increments a persisted per-demand cycleSequence on successful fulfillment, and writes OrderCycleCompleted events to a checkpointed outbox after resource settlement and reservation release. ApplicationService and the Godot Bridge expose pending reads and idempotent acknowledgments. Space's WorldV2RuntimeNode and WorldV2ShipHost now forward those APIs to GDScript. This is a real event channel; completion must never be inferred from a UI snapshot.

## 4. Space effect dispatcher

Space should resolve each successful completion event through the immutable effect binding captured by the active pre-battle loadout.

Responsibilities:
1. Validate that the event belongs to the active ship-world and a selected order binding.
2. Deduplicate by eventId before applying effects.
3. Resolve the exact effectDefinitionId + version captured for this battle.
4. Apply the effect through the Space combat/world effect system.
5. Record the event as processed and retain enough state to recover safely after save/load or interruption.

The effect catalog may eventually include cooldown buffs, temporary modifiers, triggered combat actions, support effects, or non-combat world effects. Their detailed semantics are Space-owned. No particular stacking, refresh, target, or numerical effect rule is implied here.

A successful event may produce no effect if the Space binding explicitly defines a no-op/disabled outcome; it must never fall through to an unrelated default reward.

## 5. Resource import: typed energy stones and Jar liquids

Space owns the physical energy-stone drops and pickup lifecycle. The established design says energy stones are typed by shape/property; the universal processor accepts all stone types and contributes to the corresponding shape-specific Jar production progress. Different production devices may have different per-shape processing rates. Production progress is independent per shape, and completing a unit produces a Jar.

This processing is distinct from importing a liquid into the Jar ship liquid inventory. The current Jar ship liquid inventory is a bounded liquid-only inventory; it does not represent the energy-stone input buffer or shape-progress accumulator.

Keep two ingress paths distinct:

- **Energy-stone ingress:** Space pickup identity/type/quantity -> configured production-device processing input -> shape-specific processing progress -> Jar output. Device configuration and progress persistence must be explicit; do not route stones through ship-liquid inventory production.
- **Liquid ingress:** only if Space has a separate approved source of actual Jar liquid, use an idempotent liquid-import command into the ship liquid inventory.

The current World V2 Bridge exposes neither a production-device energy-stone ingress command nor a generic Space-liquid import command. Both are future adapter/API work.

For energy-stone ingress, the eventual receipt must report source identity, accepted quantity, processed/remainder quantity, and output Jars/progress delta. Replaying the same pickup identity must not process it twice. Whether unprocessed stones are retained, rejected, or discarded must be explicit; do not silently destroy Space-owned pickups.

## 6. Completion event durability

A bounded resource ledger and detached world snapshot are not a durable completion-event channel.

Required implementation:
- successful cycle completion writes an outbox event only after resource settlement, reservation release, demand fulfillment/cooldown transition, and cycle sequence increment;
- event identity, per-demand cycle sequence, Jar world-instance identity, and pending events survive the version-2 execution checkpoint;
- read/ack operations are exposed through ApplicationService/Bridge using detached DTOs and are now surfaced through the Space runtime/ship host;
- events remain available until Space acknowledges them;
- duplicate reads and retries return the same event; acknowledgment is idempotent;
- Space's effect dispatcher deduplicates before applying the effect.

Do not invoke Godot or Space callbacks from Jar Core during a mutation. Jar records the fact; the Space host drains the detached outbox through a controlled application boundary.

## 7. Resource and save transaction boundary

For any future Space-to-Jar resource transfer:
1. Space persists a pending intent with a stable source/operation identity.
2. Space submits the import command.
3. Jar atomically records its receipt and inventory/progress mutation.
4. Space finalizes only the accepted amount.
5. Retrying the same operation returns the original receipt.

For order effects:
1. Jar persists the successful-cycle outbox event.
2. Space resolves the event against the battle's immutable effect binding.
3. Space applies the effect idempotently using eventId.
4. Space acknowledges the event after its own effect state and processed-event identity are durable.

Space and Jar do not share one database transaction. Save recovery must use stable operation/event IDs and idempotent application, not assume cross-system atomic writes.

Space now has a frozen-loadout snapshot contract and a callback-driven order-effect dispatcher boundary. The dispatcher will not acknowledge an event until the injected Space commit callback reports that both the effect state and processed EventId were durably saved. The callback and battle save/load wiring remain to be implemented; until then, the dispatcher must not be treated as an active effect path.

## 8. Explicitly not decided

This contract does not yet choose:
- numerical buff effects, durations, targets, stacking, refresh, or interaction rules;
- whether all selected orders are buffs or whether some produce other world effects;
- exact energy-stone shape vocabulary, per-device rate tables, or partial processing policy beyond the established shape-specific progress model;
- whether and how any other Space resource imports as liquid;
- the player interaction that initiates workshop replacement during combat;
- final save-file format and cross-system recovery orchestration.

These are separate design/data tasks. The boundary is fixed: Jar reports successful order cycles; Space owns their gameplay effects.


## 9. Skill activation and Active/Passive assignment

Every player-configurable combat capability is a Space skill, regardless of whether its effect is a projectile, beam, missile, shield, support unit, reconnaissance action, or combat modifier. Effect category is independent of control area.

- **Active**: the player requests the exact demand ID. The request enters Jar's normal admission/execution path; Core decides feasibility, resource availability and cooldown.
- **Passive**: Jar Core's Passive demand scheduler owns automatic admission attempts. Passive is not free or continuously active; every successful cycle consumes the configured resources and observes the same Core cooldown rules.
- Space owns the benefit/effect definition, target policy, duration, stacking, and the implementation that creates the projectile/beam/shield/drone/recon effect.
- Any future battlefield-context trigger policy belongs to Space, but it may only decide whether to submit a request; it must not duplicate Jar feasibility or cooldown logic.
- Active/Passive is independent of effect category. A shield, beam, missile or drone may occupy either lane.

The current effect registry is Buff-first. Typed non-Buff effect definitions and executors remain implementation work; do not model a projectile or support unit as a fake BuffDefinition.

Space effect implementation added on the current branch:
- Buff definitions carry explicit positive versions and are resolved by exact version through SpaceEffectCatalog.
- Buff instance state includes remaining duration, stack count, tick progress, target key, and a custom-state extension point.
- StatusEffectManager captures/restores active instances and processed event IDs; restore validates into a staged set and rebuilds stat modifiers without replaying gameplay callbacks.
- SpaceOrderEffectCommitter applies a Jar event idempotently and persists the effect state with the proposed dispatcher state before the dispatcher acknowledges Jar.
- The state store uses a pending file plus recoverable previous snapshot; platform-specific crash/replace behavior remains to be validated and full battle save/load integration is still outstanding.


## 8. Audited Jar liquid-cost semantics

The authoritative Jar requirement entry contains a required shape and an optional target liquid; it does not contain a numeric liquid amount. Numeric free-liquid demand is derived from the concrete solver plan and its resource manifest:
- POUR_IN consumes one free-liquid unit.
- Empty-Jar RESHAPE consumes one free-liquid unit of its cost liquid.
- Full-Jar RESHAPE consumes the liquid already inside the Jar.
- POUR_OUT returns the Jar's liquid to the order staging balance.

For B-class orders, the slave transfer quantity is independently derived from the slave execution path. Only the required amount is transferred from Master to Slave.

Space must not add a synthetic `liquidUnits` property to Jar requirements. Recipe-only battle forecasts carry a separate, named `resourceCostForecast`; a resolved Jar manifest is the authoritative quantity when a concrete plan is available. See `11-real-resource-contract-audit.md`.
