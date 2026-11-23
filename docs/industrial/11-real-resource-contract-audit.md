# World V2 × Space — real resource contract audit

Status: first cross-repository audit; production catalog ingestion is not yet available.

## 1. Jar's authoritative requirement contract

The current Jar World V2 contract is qualitative at the requirement level:

- A Jar requirement is represented by a required shape and an optional target liquid. The World V2 solver receives the typed `JarOrderSpecification`; the demand board and checkpoint preserve that specification rather than interpreting Space-specific numeric liquid fields.
- `WorldOrderResourceManifest` derives actual liquid supply from the resolved execution plan, not from counting liquid-bearing requirements.
- A `POUR_IN` consumes exactly one free-liquid unit of its target type.
- A non-full `RESHAPE` consumes exactly one free-liquid unit of its cost type.
- A full `RESHAPE` consumes the liquid already inside that Jar; it does not consume one additional unit from the free-liquid pool.
- A `POUR_OUT` returns the Jar's existing liquid to the current order's staging balance.
- The manifest computes prefix-peak initial supply, final balances, and A/B transfer supply from the concrete path. For B, the slave transfer amount is recomputed from the slave path; excess master liquid is not pumped to the slave.

Therefore **Jar requirements do not contain a numeric `liquidUnits` field**. A Space forecast must not add one to the Jar requirement or treat one liquid-bearing Jar as one unit of external liquid cost. Actual external demand depends on the selected physical Jar states and the resolved operation path.

The bridge now keeps these facts separate:
- `jarOrder.requirements[].shape/liquid`: authoritative Jar request.
- `resourceCostForecast.liquidUnitsPerActivation`: Space-side forecast, with an explicit `forecastSource`; it is not sent to Jar.
- Where an execution plan/manifest is available, its initial supply and transfer amounts are the authoritative per-plan quantities. A recipe-only forecast must identify its scenario assumptions (for example, empty-Jar start state).

## 2. Jar time and production units

- World V2 logical time uses 1000 milliseconds per logical time unit.
- `WorldV2Options.Producers[].Rates` and `LiquidProductionRates` are quantities per logical time unit, not per real-world second.
- Jar's ship liquid inventory uses integer units and one shared total capacity across liquid types. It tracks balances, used/available capacity, and reserved return capacity.
- Liquid production is deposited into ship liquid inventory; capacity overflow is explicitly discarded. It does not automatically flow into a workshop staging account.
- Jar production and liquid production have their own fractional accumulators, so a continuous-rate estimate is not equivalent to integer production at each simulation step.

Space must convert its simulation-time horizon to Jar logical time deliberately. The current evaluator's per-second rates are a Space forecast unit; an adapter must perform the unit conversion and preserve tick/accumulator assumptions.

## 3. Workshop constraints

Jar's world configuration defines a roster of workshop instances and fixed Master/Slave role references. Each workshop carries:
- supported base/additional shape marks;
- liquid bans;
- maximum Jar count;
- maximum liquid count and an optional shared liquid staging capacity.

The authoritative solver uses current workshop snapshots, modifier projections, Jar states, and the A/B execution partition. A-class plans are single-phase Master plans and have no slave resource transfer. B-class plans require an empty Slave at solve start and use a one-way Master-to-Slave transfer equal to the slave path's required initial free liquid. The Slave receives no independent ship-liquid feed.

The Space evaluator's current single `workshopOperationsPerSecond` pool is therefore only a coarse forecast. It cannot represent per-instance capabilities, staging peak capacity, one active Slave lease, A/B admission, or plan sequencing. Those must come from a selected workshop-combination profile and eventually a concrete Jar solve/manifest projection.

## 4. Space-side asset audit

The current World V2 integration branch contains the evaluator, skill/effect definitions, loadout snapshot, sandbox World V2 JSON, and probes. The sandbox JSON is a deliberately small test fixture (two shapes, two liquids, one simple producer, two workshops); it is not a production ship/device/workshop catalog.

The current branch documentation explicitly records that:
- Hangar does not yet materialize a production loadout from real catalogs;
- the Space branch now contains versioned weighted drop-profile data, a stable-ID pickup adapter/spawn API, typed energy-stone ingestion, independent per-shape parser progress, and whole empty-Jar batches; jar-system-dotnet PR #59 provides the idempotent central-warehouse import boundary; actual enemy death call sites and production drop/parser values are still not connected; legacy Asteroid wallet ore remains a separate resource;
- production ship/drop, production-device, liquid-stock/rate, and workshop-combination catalog assets have not yet been connected.

Accordingly this audit does not invent enemy drop rates, stone shape distributions, device processing rates, workshop operation costs, or skill recipes. Those values must be read from actual assets or introduced as versioned game-design profiles before numerical calibration.

## 5. Bridge correction in this phase

`SpaceJarRequirementCostAdapter` counts physical required Jars by shape from the exact Jar requirement array, while accepting liquid quantities only from a separate named Space forecast. It validates that forecast liquid keys correspond to liquids requested by the Jar order and that quantities are finite non-negative whole units. It does not assume one unit per liquid-bearing Jar.

`SpaceBattleEconomyEvaluator` consumes this separated forecast. Missing liquid forecasts fail closed when the order requests liquid. This preserves the Jar domain contract and makes the uncertainty visible to designers.

## 6. Next implementation boundary

1. Add versioned ship acquisition profiles with low/standard/high battle pickup scenarios.
2. Add versioned production-device profiles with per-shape processing throughput and progress carry-over.
3. Add a versioned Jar-world resource profile that mirrors validated World V2 options, including logical-time units, initial liquid stock, shared capacity, and producer rates.
4. Add workshop-combination profiles that preserve actual roster instances and A/B constraints rather than a single operation-rate scalar.
5. Build scenario materializers that create evaluator inputs from frozen loadouts and named assumptions.
6. When a concrete Jar execution plan is available, use its resource manifest for actual initial liquid supply/transfer; retain recipe-only estimates as explicitly labeled forecasts.
7. Calibrate the benefit/cost curve only after representative real profiles and acquisition scenarios exist.


## 7. Versioned Jar-world resource profile adapter

Added `SpaceJarWorldResourceProfile.gd` as a versioned wrapper around the actual `WorldV2Options`-shaped configuration. It validates the Jar liquid vocabulary, whole-unit initial stock, shared ship-liquid capacity, liquid production rates, producer shape keys, workshop roster, fixed Master/Slave references, and workshop staging constraints before exposing either:
- a deep-copied `jarWorldOptions` payload for the frozen loadout; or
- the liquid-side fields consumed by the Space battle economy evaluator.

The rate conversion is explicit: Jar production is per logical time unit and one logical time unit is 1000 logical milliseconds. Since the evaluator horizon is also expressed in logical milliseconds, the numerical rate is preserved when projected as per logical second. This adapter does not create shape-Jar output or workshop operation capacity; those remain separate acquisition/device and workshop-combination inputs.

`SpaceJarWorldResourceProfileProbe.gd` checks the materialized liquid stock/capacity/rate contract and rejects initial stock exceeding the shared capacity. It uses synthetic fixture values only; no production profile is claimed.


The profile's liquid-side materialization carries `jarResourceProfileId` and `jarResourceProfileVersion` into the battle forecast. The evaluator preserves this provenance in its report and rejects an initial stock total above the configured shared capacity. The projected production total may still exceed capacity over the full battle horizon; that is reported as a no-consumption overflow risk until time-resolved consumption/production scheduling is implemented.


The profile preflight additionally checks the positive execution logical-time unit, finite non-negative Jar flow rates, unique producer names, workshop shape-mark vocabulary/uniqueness, liquid-ban vocabulary, positive workshop Jar/liquid capacities, and optional non-negative staging capacity. Jar Core remains the final authority and repeats its own WorldV2Options validation.
