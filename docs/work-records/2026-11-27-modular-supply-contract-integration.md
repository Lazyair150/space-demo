# 2026-11-27 Modular supply contract integration

## Goal

Advance the modular gameplay systems using their written contracts as the implementation guide, and collect their synthetic contract probes into the existing domain suite. Avoid waiting for a separate CI run after each small module edit.

## Source baseline

- Space repository: `Lazyair150/space-demo`
- Branch: `world-v2/phase-4.10b-hangar-ui`
- Starting Space head: `afb3f439a18ef193407ddc87d30d904b5bdf449e`
- Core repository: `Lazyair150/jar-system-dotnet`
- Core integration target: `f4f2151db445afc794d34d8d7d1932dd0d3b40dd`
- Core PR #63 verify run: `45867857842`, completed SUCCESS on the exact target SHA above.

## Development changes

### 1. Aggregate existing module contracts

Updated `scripts/industrial/world_v2/SpaceDomainContractProbe.gd` to include:

- `SpaceBattleJarSupplyForecastProbe`
- `SpaceBattleSupplyReconciliationProbe`

These modules already had their own deterministic synthetic fixtures. They were not included in the common domain-contract aggregation, so the standard cross-repository run could report the domain suite green without executing these two module contracts. The aggregation now makes them part of the normal domain suite.

The probes use synthetic values only. They validate fixed-point source separation, Parser throughput limits, Low/Baseline/High monotonicity, exact receipt accounting, Parser completed/pending/acknowledged conservation, separate Core account balances, and refusal to invent per-Jar source attribution.

### 2. Align the Core integration pin

Updated `.github/workflows/world-v2-cross-repo.yml` to pin both checkout and `CORE_EXPECTED_SHA` to the verified Core commit:

`f4f2151db445afc794d34d8d7d1932dd0d3b40dd`

The previous pin `35f666720115fed0b2103001ad1c450fba4a65c9` lagged behind the current Core PR head. The workflow now builds the same Core source revision that passed Core verification.

## Module contracts retained

- Forecast is a read-only scenario estimate, not a promise of actual Core admission or deterministic enemy/drop outcomes.
- Parser completed output and Core import receipts remain distinct facts.
- Core Warehouse, Master Workshop and Slave Workshop balances remain separate accounts.
- Historical Parser stored/discarded receipts are not misrepresented as current per-Jar provenance.
- Progression reward settlement remains a separate durable boundary; XP amounts and curves must come from versioned content policy, not hardcoded service coefficients.

## Validation boundary

- Core verify run `45867857842`: SUCCESS on `f4f2151db445afc794d34d8d7d1932dd0d3b40dd`.
- Space changes in this record have been committed to the integration branch.
- No new Space workflow result is claimed here; the next full cross-repository run should execute after the grouped module changes.
- No desktop GUI acceptance is claimed.

## Next grouped development batch

1. Review supply forecast output integration against the real stage/loadout composition; retain the distinction between scenario estimates and actual receipts.
2. Connect only committed gameplay facts to the existing reward settlement boundary, with explicit event provenance and durable settlement ownership. Do not invent XP balance values.
3. Review MainMenu/Hangar/Battle transitions and World Host release as one application lifecycle, rather than isolated UI callbacks.
4. Once the module batch is coherent, run the complete Core + Bridge + Space import/build/domain/runtime/lifecycle validation once, then perform desktop GUI acceptance.
