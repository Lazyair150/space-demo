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

Energy stones are finite Space-world pickups. Each stone has a type/property corresponding to one Jar shape, and its volume is the amount of parseable progress it contributes. The universal parser accepts every configured type; types are processed independently and in parallel, with one queue and one fractional progress accumulator per shape.

The selected parser is a versioned pre-battle production-device definition. Adding the required parser selection advances `SpaceBattleLoadoutSnapshot` to schema version 2. Its `productionPercentage` is an attribute of that parser: it scales the parser's own per-shape processing throughput. It is not a percentage allocation among Jar shapes and is not stored on the energy-stone type. The parser also defines its per-shape processing rates and progress required for one Jar.

The Space-owned `SpaceOreParserRuntime` consumes finite queued stone volume at the selected parser's effective rate, retains unprocessed stone volume and sub-Jar progress, and emits a batch only when a whole Jar threshold is reached. Batches carry stable operation IDs and remain pending until Jar confirms import. `SpaceOreParserJarIngress` submits those batches through `WorldV2ShipHost.ImportProducedJars`; Jar creates empty Jars in its central warehouse and owns capacity, overflow discard, warehouse-to-Master flow, and all downstream order rules.

This is deliberately not the time-based World V2 Producer rate model. `UpdateProducerRates` remains a separate generic API for configured time-driven producers and must not be used to represent finite energy-stone consumption. The parser runtime checkpoint retains pickup identities, queued remaining volumes, independent per-shape progress, fixed-point rate remainders, pending output batches, and the next batch sequence. Jar's resource-ledger operation IDs make retries safe across Jar checkpoint restore.

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

The dispatcher is an integration boundary, not yet a complete live combat feature: no Hangar currently constructs the snapshot or wires the catalog/effect manager/store/committer instances into Game. The concrete `SpaceOrderEffectCommitter` and `SpaceBattleEffectStateStore` now implement Buff resolution, durable effect+dispatcher+Jar/Space checkpoint replacement, and restore payload validation, but normal gameplay does not yet construct/configure them. If a loadout selects orders without a valid callback, Game.gd fails closed and does not enter combat.

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
- production Hangar construction of the immutable loadout from real ship/device/workshop/order catalogs (the frozen-loadout Runtime path itself is implemented);
- live Hangar selection/materialization of the Space-owned ore parser definition and actual enemy/pickup wiring;
- Hangar/pre-battle UI and construction of the immutable snapshot from actual ship/device/workshop/order catalog selections;
- binding the selected orders' orderDefinitionKey values to the actual Jar demand creation calls;
- wiring `SpaceBattleEffectStateStore` and `SpaceOrderEffectCommitter` into the real Hangar/battle save lifecycle;
- restoring the saved `effectState` into `StatusEffectManager` before combat resumes (Game restores Jar, clock, parser, pickup, and dispatcher state after the caller supplies the snapshot);
- platform-tested durability/atomic replacement behavior on the supported save targets;
- making the frozen-loadout path the normal Hangar-to-combat path and disabling the sandbox development fallback in production.

Implement in that dependency order. Do not wire an order to a BuffDefinition until the Jar event identity and durable delivery contract exist.


## 11. Versioned Skill Catalog foundation

The branch now contains `SpaceSkillDefinition.gd` and `SpaceSkillCatalog.gd`:
- A skill definition owns its stable skill ID/version, player-facing name/description, Jar execution contract (A/B type, Jar demand area, requirements, cooldown), and Space effect binding (effect ID/version/parameters).
- Jar cost is represented by the Jar requirements/configuration itself. There is no separate balance number that can drift away from actual Jar consumption.
- When equipping, the player selects Active or Passive from the skill's allowed control areas. That selection is materialized as the Jar demand area and the Space activation policy (manual or automatic); there is no second conflicting area value.
- Active maps to a manual activation request; Passive maps to automatic trigger policy. This is a control assignment, not a different effect type or a bypass around Jar.
- SkillCatalog resolves exact skill versions and produces the selected-order binding consumed by the frozen battle loadout.

This is the definition/registry/materialization foundation. Actual catalog assets, Hangar UI, manual activation command flow, passive trigger scheduler, and catalog compatibility validation are still outstanding.


## 12. Skill benefit-to-Jar difficulty curve (the balance bridge)

The skill model is not "effect plus arbitrary recipe". The Space benefit is the value side of the curve; the exact Jar execution contract is the payment side. The two are evaluated together before a skill binding can enter a frozen battle loadout.

### Benefit side

Each skill carries a normalized `benefitProfile` with dimensions such as:
- power;
- duration;
- coverage/area;
- control;
- survivability;
- utility.

The metrics are stored on the exact versioned effect definition (`BuffDefinition.balance_metrics` for the current Buff executor), beside its real modifier/tick/duration data. They are not separately authored on the skill resource, preventing a skill from claiming a stronger benefit than the effect version it actually invokes. A versioned `SpaceSkillBalanceProfile` supplies per-dimension scales and weights. Designers must update the metrics and increment the effect version whenever gameplay meaning changes. These are tunable annotations, not fixed balance truths.

Jar cooldown also affects sustained value. Shorter cooldown permits more executions over the same Space battle time, so the model applies a configurable activation-frequency multiplier derived from `cooldownDurationLogicalMilli`. A zero cooldown is bounded by a configurable floor and maximum multiplier; it cannot create an infinite value.

### Payment side: actual Jar difficulty

The evaluator reads the exact Jar requirement entries that will be materialized. Each normalized entry represents one physical required Jar. A grouped skill-authored requirement with `count=N` is expanded into N individual Jar requirement entries before both evaluation and Jar materialization. This is important: count must never be a display-only number that the Jar bridge silently ignores.

The build-context evaluator first applies the selected parser's `productionPercentage` to its own per-shape processing rates, then estimates output per shape as `min(expected ship stone progress rate, effective parser processing rate) / progress required per Jar`. It estimates expected skill activations over the configured battle horizon and calculates pressure separately for each required shape. The worst shape bottleneck controls production pressure; a plentiful shape cannot hide a shortage of another shape. Unsupported ship-drop, processor, or shape-conversion combinations fail closed. Workshop operation cost is derived from the selected workshop combination and includes an explicit per-liquid-Jar handling cost.

The first cost model includes independently visible terms:
- total required Jar count;
- number of liquid-bearing Jars;
- distinct liquid variety;
- distinct shape variety;
- per-shape and per-liquid difficulty multipliers;
- A/B order execution class;
- workshop-operation pressure supplied by the selected workshop combination;
- production pressure supplied by the selected ship's expected stone yield and the selected production-device processing throughput.

Liquid-bearing Jars are intentionally more expensive than empty Jars in the default tuning profile. This is a balance parameter, not a hard-coded Jar rule. Liquid type and shape scarcity can further modify the cost through versioned profile data.

### Curve and diagnostics

The first curve is:

`targetDifficulty = baseDifficulty + coefficient * effectiveBenefit ^ exponent`

`difficultyRatio = actualJarDifficulty / targetDifficulty`

The evaluator reports:
- `undercosted`: Jar payment is below the target curve;
- `on_curve`: payment is within the configured tolerance;
- `overcosted`: payment exceeds the target curve.

It also returns a component breakdown so a designer can see whether cost comes from liquid Jars, variety, workshop complexity, production pressure, or the order class. The evaluator does **not** auto-invent recipes or alter Jar requirements to force a score. Recipe generation/optimization is a later design tool; the current model diagnoses and compares authored recipes without hiding their actual cost.

### Important non-equivalences

- Benefit score is not the same as a Buff's raw numeric magnitude. It is a normalized balance measure across heterogeneous effect dimensions.
- Difficulty score is not simply total Jar count. Liquid-bearing Jars, shape/liquid diversity, and build-specific processing constraints matter.
- Jar cooldown is not effect duration. Cooldown contributes to how often the skill can produce value; effect duration contributes to how much benefit each activation delivers.
- The Active/Passive control area does not itself make a skill stronger or cheaper. It determines who requests execution. Both modes pay the same Jar contract.

### Current implementation

Added:
- `BuffDefinition.balance_metrics`: versioned benefit annotations stored beside the actual effect definition; SpaceEffectCatalog resolves them by exact effect ID/version.
- `SpaceSkillBuildContextEvaluator.gd`: derives shape output pressure from expected ship stone-progress input, the selected parser's percentage-scaled per-shape throughput, and progress-per-Jar; derives workshop and liquid-handling operation pressure from the selected workshop combination.
- `SpaceOreParserDefinition.gd` and `SpaceOreParserRuntime.gd`: version the pre-battle parser percentage/rates/thresholds, ingest all configured stone types, preserve independent fixed-point progress, and emit idempotent whole-Jar batches.
- `SpaceOreParserJarIngress.gd`: retries pending parser output batches through Jar's discrete `ImportProducedJars` boundary and acknowledges only after Jar confirms success.
- `SpaceSkillBuildContextEvaluatorProbe.gd`: verifies that parser percentage scales its own shape throughput and does not redistribute production between shapes.
- `SpaceOreParserJarIngressProbe.gd` / `SpaceOreParserJarIngressProbe.tscn`: end-to-end synthetic probe for parsing, central-warehouse import, lost-receipt retry, and no direct Master injection.
- `SpaceSkillBalanceProfile.gd`: versioned tunable weights, scales, curve parameters, cooldown frequency bounds, resource multipliers, and difficulty bands.
- `SpaceSkillBalanceModel.gd`: deterministic evaluator and cost breakdown.
- `SpaceSkillBalanceModelProbe.gd`: checks that liquid Jars increase difficulty, stronger benefits raise target difficulty, shorter cooldown raises sustained target value, and more complex resource requirements increase actual difficulty.
- `SpaceSkillDefinition.gd`: carries benefit metrics, expands grouped requirement counts to individual Jar entries, evaluates the curve, and includes the balance report/profile identity in the generated binding.
- `SpaceBattleLoadoutSnapshot.gd`: rejects selected skill bindings without a valid balance report and versioned balance-profile identity.

The model's current numeric weights are starter tuning defaults only. The context contract now consumes expected ship stone-progress rates, per-shape processor throughput, per-shape progress-per-Jar, and workshop operation costs. Production-device and ship encounter catalogs still need real data assets and calibration; the parser runtime itself is implemented, but no production percentage/rate/threshold values are fabricated. Liquid-bearing Jars already add explicit cost and workshop handling pressure, but liquid availability still needs to be projected from the Jar liquid stock/production contract using its audited time units; do not infer liquid supply from the shape-stone processor rates. The next iteration is to wire the actual ship/drop and Jar liquid-supply profiles, then calibrate the curve against representative battle duration and observed resource acquisition. That is the step that turns the first measurable curve into the complete Space↔Jar economy model.


## 14. Shared battle economy forecast (first implementation)

The single-skill benefit/cost curve is now complemented by a battle-horizon, whole-loadout forecast:

- `SpaceBattleEconomyEvaluator.gd` evaluates all equipped skills against shared shape-Jar, liquid, and workshop-operation budgets.
- Shape-Jar supply is calculated from initial whole-Jar stock plus battle-horizon production, then floored to indivisible Jar units.
- Liquid supply is calculated independently from initial liquid stock and liquid production rate. Liquid is not inferred from energy-stone or shape-processor throughput.
- Every liquid-bearing Jar requirement must specify explicit `liquidUnits`. The evaluator rejects missing quantities rather than guessing that one filled Jar always means one unit.
- Each skill's theoretical activation ceiling is bounded by its Jar cooldown and the expected battle duration. Active skills require an explicit `requestedActivations` planning assumption; Passive skills may use the cooldown ceiling as a forecast until a real trigger policy exists.
- All equipped skills compete for the same resource and workshop budgets. The current first-pass allocator applies a deterministic common fulfillment fraction and reports bottlenecks; it deliberately does not invent priority or scheduling policy.
- Liquid inventory capacity is instantaneous storage capacity, not lifetime throughput. Because consumption timing and production tick timing are not yet simulated, the current report preserves cumulative potential supply and separately reports initial-storage overflow risk. It must not be interpreted as a time-exact inventory simulation.
- Workshop operations are forecast as a shared battle-horizon budget. Real per-workshop concurrency, A/B session constraints, and operation sequencing still need to be derived from the selected Workshop combination data.

The balance model's cooldown adjustment now compares expected activation counts over the configured battle horizon against the profile's reference cooldown, instead of treating cooldown as a horizon-free ratio. The earlier ratio fallback remains for isolated formula probes only; production loadout validation requires a valid duration-bearing build context.

### Probe and current limits

`SpaceBattleEconomyEvaluatorProbe.gd` checks:
1. A single liquid-bearing skill is constrained when the shared liquid/workshop budget cannot support all cooldown-available activations.
2. Adding a competing skill cannot improve the shared fulfillment fraction.
3. A liquid-bearing requirement without an explicit liquid quantity is rejected.

This is an explicit synthetic probe, not a claim that real ship/device/workshop catalog values have been calibrated. The model is a deterministic forecast, not the Jar runtime's authoritative resource ledger. It does not yet simulate exact event chronology, fractional production accumulators, inventory overflow after each production tick, Jar reservation/settlement, or priority among Active/Passive skills. Those belong to the next integration/calibration stage and must be supplied by actual versioned catalogs and Jar contracts.


## 15. Cross-repository resource-contract audit and forecast boundary

The audit is recorded in `docs/industrial/11-real-resource-contract-audit.md`. Jar requirement entries contain `shape` and optional `liquid`, not numeric liquid units. The Jar solver's resolved operation plan determines actual free-liquid cost: POUR_IN and empty-Jar RESHAPE consume one free-liquid unit; full-Jar RESHAPE consumes the liquid already inside the Jar; POUR_OUT returns it to order staging. The resulting manifest computes required initial supply and B transfer quantities from the concrete path.

The battle forecast no longer accepts a fictional `liquidUnits` member inside Jar requirements. It requires a separate `resourceCostForecast` with `liquidUnitsPerActivation` and a non-empty `forecastSource`. This is a Space-side estimate, not a Jar demand field. It may be based on a named initial-Jar scenario or, when available, a resolved Jar execution manifest. The adapter verifies liquid identities against the Jar requirements and does not infer one unit per liquid-bearing Jar.

The same audit confirms that Jar production rates are per logical time unit (1000 logical milliseconds per unit), ship liquid capacity is shared across liquid types and measured in whole units, and the current sandbox file is not a production catalog. Actual enemy drop/acquisition, stone shape distribution, production devices, and workshop combinations remain unconnected; no numeric balance calibration is claimed.


## 15. Space-owned ore parser runtime and discrete Jar ingress

The parser is a Space-owned runtime, not a Jar time-driven Producer:

- SpaceOreParserDefinition is a versioned pre-battle device definition. Its productionPercentage scales that parser's own per-shape throughput; it does not allocate output percentages among shapes.
- The universal parser accepts every configured stone type. Stone type selects the target Jar shape; finite stone volume is parseable progress. Each shape has its own input queue, fractional Jar progress, and rate remainder.
- Parsing consumes only available stone volume. Unprocessed volume remains queued; incomplete Jar progress remains accumulated independently by shape.
- A complete Jar creates a stable, pending batch ID. The parser retains that batch until Jar confirms it.
- ImportProducedJars is a discrete handoff of already-completed empty Jars into the central warehouse. Jar validates shape vocabulary, enforces warehouse capacity, accounts for overflow discard, and persists operation-ID deduplication in its resource-ledger checkpoint.
- The Game physics step asks WorldV2ShipHost for the exact whole-millisecond delta once. The Host records one prepared step and rejects a second accumulation or a mismatched/repeated consume. Space parses and imports with that delta before Jar advances by the same delta. There is one fractional-millisecond accumulator, owned by the Host.
- Parser state capture includes pickup identity/deduplication, queued remaining volume, per-shape fractional progress/rate remainder, pending output batches, and the next batch sequence.

The Godot end-to-end probe covers a synthetic stone becoming a Jar, a simulated lost import receipt, retry through the same operation ID, and the invariant that imported Jars enter the central warehouse rather than a workshop.

EnemyChaser and EnemyShooter now expose optional versioned SpaceEnergyStoneDropProfile data; Spawner routes their death event through a separate energy-stone channel alongside the existing Buff capsule channel, and may override the ordinary enemy profile with a distinct elite-wave profile so larger stone volumes are authored as data rather than hard-coded behavior. Game freezes the profile, validates types against the frozen Jar shape vocabulary, allocates a persisted stable pickup ID, and instantiates SpaceEnergyStonePickup. Remaining integration work is production data/ownership: Hangar must freeze a real parser profile into the loadout; production enemy/encounter profiles must be authored; the real save/load lifecycle must invoke SpaceBattleEffectStateStore/SpaceOrderEffectCommitter and restore the saved effectState into StatusEffectManager. The unified store already commits effect/dispatcher/Jar/Space/parser/pickup/RNG/run progression in one checkpoint. Player health/position, enemy instances, wave scheduler state, and platform durability still need a complete save coordinator. The pickup adapter forwards successful player collection to Game.ingest_energy_stone and only removes the pickup after parser acceptance. No production rates, drop volumes, or parser percentages are fabricated here.

### Parser runtime integrity follow-up

The selected parser definition is copied into the runtime at initialization; mutating the source Resource later cannot alter the active battle parser or its checkpoint fingerprint. Parser runtime state schema v2 stores explicit pickup type/original volume records. Restore validates exact configured shape maps, pickup-to-queue correspondence, fixed-point progress and rate remainders, parser-instance-scoped pending batch IDs, and positive bounded Jar counts before replacing any live state.

Each parser advance now computes against staged copies. Arithmetic overflow or a per-step Jar import count above the Bridge's Int32 batch limit rejects the step without consuming queued stone volume, changing progress, or changing rate remainders. The synthetic probe checks both rejection paths and verifies the parser state remains byte-for-byte/value-equivalent after rejection. Progress-per-Jar thresholds below the one-micro-unit fixed-point resolution are rejected during definition/loadout validation.

### Enemy drop profile and stable pickup identity

EnemyChaser and EnemyShooter may reference a versioned SpaceEnergyStoneDropProfile. Spawner handles the enemy death event once, then independently resolves the legacy Buff drop and optional energy-stone drop. The profile maps a configured Jar shape/type to a finite volume and relative weight; the absence of a profile means no energy-stone drop. The current enemy scenes have no profile assigned, so this infrastructure does not alter existing gameplay drop rates.

Game owns the stable pickup sequence and emits IDs scoped to the frozen ship-world identity. The sequence is captured with parser state. SpaceEnergyStonePickup delegates collection to Game.ingest_energy_stone and is removed only after parser acceptance; a duplicate identity with the same payload is idempotent, while changed type/volume is rejected and leaves the pickup in the world. Game's parser envelope captures and restores the stable sequence, every uncollected pickup's typed payload/world position, and the Spawner's energy-stone RNG state. These are included in the unified Jar/Space checkpoint rather than being reconstructed from enemy drop rolls.

### Exact-version parser catalog and loadout materialization

`SpaceOreParserCatalog` is now an editor-authorable Resource with a typed `definitions` array. It builds an exact `(parserId, definitionVersion)` index and stores detached copies of registered Resources. It never silently substitutes a newer version; the catalog can be explicitly re-indexed after authoring changes. `SpaceBattleLoadoutSnapshot.create_with_ore_parser` is the pre-battle composition entry point: it reads the frozen Jar shape vocabulary, resolves the requested exact parser version, materializes it into one production-device slot, rejects duplicate parser selections/slot collisions, and only then creates the immutable loadout fingerprint. The parser's percentage, shape rates, and per-Jar thresholds therefore participate in the same immutable identity as the rest of the build.

The build-context evaluator also requires the ship's expected stone-progress profile to cover exactly the same shape vocabulary as the universal parser. Missing shape rates no longer degrade silently into zero output capacity, and thresholds below one fixed-point micro-unit are rejected before a battle can start.

### Deterministic drop checkpoint envelope

Space parser checkpoint envelope schema v2 includes the Spawner's energy-stone drop RNG state in addition to parser runtime state, next pickup identity sequence, and all uncollected pickup records. Restoring the same battle checkpoint restores the RNG stream before the next enemy drop, preventing a resumed battle from rerolling a different drop sequence. `capture_jar_space_runtime_checkpoint` groups the Jar execution checkpoint, Host fractional clock remainder, parser/drop envelope, and order dispatcher state into one object; the outer save coordinator must persist this object atomically with the frozen loadout and Space effect state.

### Coordinated Jar/Space checkpoint and exactly-once effect commit

WorldV2RuntimeNode now captures/restores the Jar execution checkpoint JSON through the Bridge using the exact WorldV2Options used to initialize the world. WorldV2ShipHost enforces step-boundary capture and pre-mutation restore. Its fractional-millisecond remainder is captured separately because it belongs to the Space clock, not Jar Core.

Game captures a loadout-bound runtime payload containing Jar checkpoint JSON, Host clock remainder, parser state, stable pickup sequence, and all uncollected energy-stone pickup records. Restore validates the frozen loadout identity, restores Jar before parser, skips re-materializing orders already present in the Jar checkpoint, and reconstructs only pickups not already accepted by the parser.

SpaceBattleEffectStateStore schema v3 writes effect state, the next dispatcher state, and this Jar/Space runtime payload into one pending/previous file-replacement transaction. The runtime payload includes parser envelope schema v2 (pickup sequence, uncollected pickup records, and drop RNG state) plus transient score/wave/segment run state. SpaceOrderEffectCommitter requires a runtime-checkpoint provider: it applies the effect, captures Jar/Space state, commits the combined snapshot, and only then returns success so the dispatcher may acknowledge Jar's outbox event. A failed save leaves the event pending. Schema v1 remains readable for legacy effect/dispatcher-only saves but cannot resume the new cross-domain runtime; earlier schema v2 snapshots are intentionally not accepted after the run-state contract change.

The integration probe now simulates a process restart after Jar accepted an import but before Space acknowledged it. It restores Jar's resource-ledger operation IDs, Space's pending parser batch, and the Host's fractional clock remainder, retries the same operation ID, and verifies one physical Jar only. The store probe verifies the combined schema-v3 persistence contract, including rejection of missing run state and missing drop RNG state.

Remaining save integration is the outer Hangar/menu orchestration: load the stored frozen loadout and effect state, configure the committer with Game.capture_jar_space_runtime_checkpoint as its provider, then pass the stored snapshot plus the exact SpaceEffectCatalog and target resolver to Game.configure_battle_loadout_from_checkpoint before adding the combat scene. Game now restores StatusEffectManager state through its staged restore API before the first combat step; the manager probe verifies exact-version resolution, duration/stacks reconstruction, processed EventId restoration, and duplicate-event suppression. No complete combat save (player HP/position, wave scheduler, enemy state) is claimed by this resource-runtime checkpoint.

### Wave progression restore boundary (2026-11-23)

The transient run checkpoint stores score, wave number, and segment label, but it does not store the live Spawner coroutine/timer, spawn cursor, alive-enemy set, enemy HP/positions, bullets, or player state. Therefore this is **not an exact mid-wave combat resume**.

On loading such a checkpoint, Spawner now restarts the saved wave from its beginning without incrementing or rewriting the saved wave/segment. A new run (wave 0) still starts at wave 1. This prevents the previous bug where Spawner unconditionally started wave 1 and overwrote the restored progression. It is an explicit wave-restart policy, not a claim that already-killed enemies or elapsed spawn delays are restored. `GameState.restore_run_state` also rejects a segment label inconsistent with its wave number before mutating live state. `SpaceBattleRunStateProbe` covers mismatched wave/segment rejection and the pure initial-wave selection policy.

Exact battle continuation remains blocked on a separate encounter checkpoint contract for spawn phase/timers, enemy identities and runtime state, player state, and projectiles. Until that exists, callers/UI must describe this path as **restart current wave from checkpoint**, not seamless combat resume.
