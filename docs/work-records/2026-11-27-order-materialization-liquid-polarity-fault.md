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

Core regression test was introduced in `b593f4a2effcd7091f80e1a31d703072c2d5f6b4`; the collection assertion was corrected in `35f666720115fed0b2103001ad1c450fba4a65c9`. The test `ApplicationOperationsPreserveExplicitNonDefaultLiquidPolarities` creates a custom World mapping `coolant → Cathode`, `fuel → Anode`, then exercises direct demand creation, Core template materialization and produced-Jar import.

Space cross-repository workflow and README are now pinned to Core source/test SHA `35f666720115fed0b2103001ad1c450fba4a65c9`. Core CI runs `45859139265` and `45859573824` caught two xUnit2013 collection-size assertions in the new test. Both test-only analyzer findings were corrected in the pinned SHA above. Fresh exact-head Verify run `45860000880` is in progress; no success is claimed yet.

## Navigation probe clarification

The previous pause/navigation probe intentionally attempts a missing scene path to test rollback, so Godot prints an expected `[GameFlow] Main-menu return failed` error. It then exercises the real Main Menu transition. The probe now emits separate markers:

- `expected-transition-rejection=passed` for the rollback assertion.
- `passed real-main-menu-transition=true` only for the actual controller-driven MainMenu return.

The cross-repository script now requires both markers. This prevents the expected negative test from being mistaken for a failed final navigation, and prevents the overall probe from passing without the rollback assertion.

## Validation state

- Board Assignment schema-v2 Core verification: previously passed (run `45856292385`).
- Liquid-polarity propagation Core verification: pending run for commit `35f666720115fed0b2103001ad1c450fba4a65c9`.
- Space cross-repository script with the new Core pin: pending.
- Desktop Hangar → World initialization → order materialization → combat: pending.
- Pause/resume → return Main Menu → re-enter battle: pending.

Do not close P0 until the exact Core run, Space integration run, and desktop GUI path are all recorded.


## Repository pointers after documentation/probe synchronization

- Space PR #2 head: `d75b4ae68b30e6b045673e059a87cf299ab571cf`.
- Core PR #63 head: `712c4b834d8320c9b535dc807ae8ab1217a68e57`.
- Space workflow and README pin the exact Core source/test revision `35f666720115fed0b2103001ad1c450fba4a65c9`.
- Core Verify run `45860000880` for the current source/test revision is `in_progress`.
- Space workflow requires both the expected rollback marker and the real MainMenu transition marker; it also requires the Board Assignment schema-v2 golden fingerprint marker.


## Latest pointer refresh

- Space PR #2 head: `c1d59247a46cd403236ce6577334456177cf892e`.
- Core PR #63 head: `b597dfafbe8e4df54b1d605f38f6863c474205a3` (documentation descendant of source/test pin `35f666720115fed0b2103001ad1c450fba4a65c9`).
- Current exact-head Core Verify run: `45860000880`, in progress.
