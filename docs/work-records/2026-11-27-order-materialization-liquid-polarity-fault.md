# 2026-11-27 Order materialization liquid-polarity propagation fault

## Desktop evidence

After the Board Assignment schema-v2 fix, the user's Godot 4.7.1 desktop log advanced past:

- `[WorldV2Runtime] initialized: frozen battle loadout`
- `[WorldV2ShipHost] Jar runtime active; external Space clock enabled`

It then failed at `WorldV2ShipHost.MaterializeSelectedOrders` while calling Core `AddJarDemandFromTemplate`:

`A non-default World must explicitly assign one Cathode and one Anode liquid identity. (Parameter 'liquids')`

This proves the earlier Board Assignment identity failure is no longer the active blocker. The failure occurs later, after the World has initialized, when an order template is materialized.

## Root cause in Core

`WorldV2Context` already stores the complete immutable World vocabulary, including `LiquidPolarities`. `Vocabulary` permits legacy inference only for the exact default liquid pair; custom World liquid identities must use the explicit mapping.

Three application-service paths were dropping that mapping:

- `ImportProducedJars`
- `AddJarDemand`
- `AddJarDemandFromTemplate`

The desktop stack hit the third path. The Core application service rebuilt `Vocabulary` from only shape/liquid names. For Space's non-default liquid names, the constructor correctly rejected the incomplete vocabulary.

## Fix and regression

Core commit `fe0b068c9e80cc232b76c91111d42fa257c227e9` changes all three call sites to pass `context.LiquidPolarities`. No Space-side name-based fallback was introduced and no Core validation was weakened.

Core regression commit `b593f4a2effcd7091f80e1a31d703072c2d5f6b4` adds `ApplicationOperationsPreserveExplicitNonDefaultLiquidPolarities`, which creates a custom World mapping `coolant → Cathode`, `fuel → Anode`, then exercises direct demand creation, Core template materialization and produced-Jar import.

Space cross-repository workflow and README are now pinned to Core source/test SHA `b593f4a2effcd7091f80e1a31d703072c2d5f6b4`. The exact Core CI run for this new head was in progress when this record was written; no success is claimed yet.

## Navigation probe clarification

The previous pause/navigation probe intentionally attempts a missing scene path to test rollback, so Godot prints an expected `[GameFlow] Main-menu return failed` error. It then exercises the real Main Menu transition. The probe now emits separate markers:

- `expected-transition-rejection=passed` for the rollback assertion.
- `passed real-main-menu-transition=true` only for the actual controller-driven MainMenu return.

The cross-repository script now requires both markers. This prevents the expected negative test from being mistaken for a failed final navigation, and prevents the overall probe from passing without the rollback assertion.

## Validation state

- Board Assignment schema-v2 Core verification: previously passed (run `45856292385`).
- Liquid-polarity propagation Core verification: pending run for commit `b593f4a2effcd7091f80e1a31d703072c2d5f6b4`.
- Space cross-repository script with the new Core pin: pending.
- Desktop Hangar → World initialization → order materialization → combat: pending.
- Pause/resume → return Main Menu → re-enter battle: pending.

Do not close P0 until the exact Core run, Space integration run, and desktop GUI path are all recorded.
