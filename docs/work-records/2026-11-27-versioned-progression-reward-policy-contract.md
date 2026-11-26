# 2026-11-27 Versioned progression reward policy contract

## Baseline

- Space branch: `world-v2/phase-4.10b-hangar-ui`
- Starting Space HEAD: `5db231d44c0ea7d2508faf0d28c2153315b1c0b8`
- Core exact pin: `116c0bb7e3589a2850bf1b85f6da4c48de8c0a28`
- Core verify: Run `45869214849`, SUCCESS.
- The previous batch established that the reward settlement service and GameState persistence entry point exist, but the battle lifecycle does not yet provide a production reward profile or call the XP settlement entry point.

## Changes in this batch

### 1. Add an explicit versioned Reward Profile

Added `SpaceProgressionRewardProfile.gd` as a content-policy boundary:

- Stable Profile ID and definition version.
- Explicit per-source-kind rules.
- Each rule declares the compatible item kind, final positive integer XP, exact Curve ID and Curve Version.
- `build_awards()` accepts only committed fact envelopes containing Event ID, Owned Instance ID, source kind and source reference.
- Unknown source kinds, missing source rules, duplicate event IDs, malformed identities, invalid XP, invalid curves and incompatible item mappings are rejected.
- The profile does not invent source facts, infer per-Jar provenance, or supply default XP values.

### 2. Bind every award to the policy version

Updated `SpaceProgressionRewardService` so every award must carry `rewardProfileId` and `rewardProfileVersion`.

- A settlement cannot mix profile identities or versions.
- The exact policy identity/version is included in normalized award fingerprints and therefore in both settlement and source-event receipts.
- Source-kind to item-kind compatibility is now owned by the Reward Profile contract rather than duplicated in the settlement service.
- Existing synthetic settlement fixtures were updated to supply explicit profile identity/version.

### 3. Contract probe

Added `SpaceProgressionRewardProfileProbe.gd` and included it in `SpaceDomainContractProbe`.

The probe uses synthetic values only and checks deterministic ordering, exact policy identity propagation, missing-source-policy rejection, duplicate Event ID rejection, incompatible item mapping rejection and the absence of implicit default XP.

### 4. Documentation

Updated:

- `docs/architecture/17-progression-stage-and-persistence.md`
- `docs/industrial/15-production-parser-and-individual-progression-gameplay.md`
- `docs/work-records/README.md`

The documents distinguish the implemented policy/settlement contracts from the still-missing production Reward Profile assets and battle fact integration.

## Important boundaries retained

- XP is awarded only from committed source facts, never from forecasts, solver candidates, pending Parser work or UI state.
- Source Event IDs and exact Owned Instance IDs remain mandatory.
- Curve ID / Version remains exact.
- No production XP coefficients, thresholds, unit conversion, rounding policy or caps were invented.
- Campaign clear persistence and XP progression persistence remain separate durable aggregates. This batch does not claim their cross-aggregate atomicity or wire the reward service into Game.gd.

## Validation status

- Core exact-head verify remains SUCCESS on `116c0bb7...`.
- Space source changes were committed as one grouped Git tree update, followed by the missing global probe class declaration.
- Space cross-repository Run `45872350494` completed SUCCESS on exact Space HEAD `068d89f0ec36164a5b6868a756527d995e729603` with exact Core pin `116c0bb7e3589a2850bf1b85f6da4c48de8c0a28`.
- Core Bridge build, Space .NET build, Godot 4.7.1 import/parse, HUD feedback, all-domain contracts (including both new progression reward probes), Parser/Core ingress, runtime, lifecycle, fault, disposed/faulted commands, snapshot isolation and battle-navigation probes passed.
- No desktop GUI acceptance or production battle reward-loop completion is claimed by this record.

## Next grouped implementation batch

1. Build the committed-fact outbox for pickup, actual Parser work, committed Core order effects and any real production/workshop facts.
2. Persist source fact IDs and outbox state in the coordinated battle checkpoint.
3. Connect an authored exact-version Reward Profile / Curve Catalog to the Hangar bundle and battle settlement callback.
4. Coordinate campaign clear and progression XP through an explicit recoverable outbox or single durable transaction; do not sequence two independent saves and call them atomic.
5. Run the full Space/Core integration suite after the module batch, then desktop GUI acceptance.

## Follow-up: first exact-pin integration log diagnosis

The run triggered by the main-branch synchronization (`45871207456`) completed with failure. Its first fatal GDScript issue was not a supply-accounting failure: `SpaceDomainContractProbe` called `SpaceBattleSupplyReconciliationProbe.run()`, but that probe script had no `class_name SpaceBattleSupplyReconciliationProbe`, so the global class identifier was not registered. The expected negative-case `push_error` diagnostics from ownership/fingerprint rejection probes were not the harness failure; the harness specifically rejects script/parse/compile/SceneTree errors.

The missing global class declaration is now added to the probe script. The progression Reward Profile batch was also committed while the exact-pin run was in progress; the next workflow run must validate both the class registration correction and the reward-policy code together.


## Exact integration result

- Run: [45872350494](https://github.com/Lazyair150/space-demo/actions/runs/45872350494)
- Space HEAD: `068d89f0ec36164a5b6868a756527d995e729603`
- Core pin: `116c0bb7e3589a2850bf1b85f6da4c48de8c0a28`
- Result: `SUCCESS`
- Both `progression-reward-profile` and `progression-reward-settlement` reported passed inside `SpaceDomainContractProbe`.
- The earlier failure was the missing global class declaration on `SpaceBattleSupplyReconciliationProbe.gd`; after adding it, the full integration script passed.
- The profile remains a contract, not an authored production balance asset. Battle fact collection and recoverable cross-aggregate reward settlement remain future work.
