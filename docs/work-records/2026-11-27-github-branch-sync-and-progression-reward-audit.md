# 2026-11-27 GitHub branch synchronization and progression settlement audit

## Source state

- Space: `Lazyair150/space-demo`
- Space branch: `world-v2/phase-4.10b-hangar-ui`
- Space source head before synchronization: `a57da17cf1fbdcc447b6eb771f0cfe4bdcbefa02`
- Core: `Lazyair150/jar-system-dotnet`
- Core branch: `architecture/core-liquid-identity-consolidation`
- Core exact head: `116c0bb7e3589a2850bf1b85f6da4c48de8c0a28`
- Core verify: Run `45869214849`, SUCCESS on the exact SHA above.
- Both PRs remain Open / Draft / unmerged.

## 1. Reconcile Space with main without discarding feature work

The Space PR was reported `mergeable=false`, with 1,258 commits ahead and 2 commits behind main. The two missing commits were inspected individually:

- `801502325df112623b3fb59ae7911f34250cd768`: adds `docs/execution/2026-11-24-cross-repo-integration.txt`.
- `8805ea665b0ff6eafa528b08630e5e8060fcad02`: updates `docs/work-records/2026-11-26-supply-reconciliation-contract.md`.

The feature branch already had a later and more complete supply reconciliation record, including the subsequent HUD integration and explicit Variant typing correction. It was preserved; the older main version was not copied over it.

A non-force merge commit was created:

- Merge commit: `85c01d6cbb3dd2f00cb0cf8043f9dd2a056c3499`
- First parent: previous Space feature head `a57da17c...`
- Second parent: main head `8805ea665b0ff6eafa528b08630e5e8060fcad02`
- Main's missing integration checkpoint was added to the merged tree.
- GitHub subsequently reported PR #2 `mergeable=true`.

No force push, reset, or deletion of feature history was used.

## 2. Align the exact Core integration source

Core PR #63 has advanced from the Space workflow's previous pin `f4f2151d...` to `116c0bb7e3589a2850bf1b85f6da4c48de8c0a28`.

A direct Core compare shows that this one-commit difference contains only a work-record documentation update; no Core runtime/API source files changed. The newer exact SHA has its own successful verify run `45869214849`.

The following Space references are being aligned to `116c0bb7e3589a2850bf1b85f6da4c48de8c0a28`:

- `.github/workflows/world-v2-cross-repo.yml`: checkout ref and `CORE_EXPECTED_SHA`.
- `README.md`: clone/build pin and cross-repository verification command.
- `docs/execution/2026-11-24-cross-repo-integration.txt`: authoritative status header.

Run `45870822329` was triggered by the branch merge before this pin update and still uses `f4f2151d...`; it must not be used as evidence for the new exact pin. The next workflow run is the relevant Space integration result.

## 3. Module audit: avoid rebuilding completed supply work

The following capabilities already exist and are connected; this batch must not duplicate them:

- `SpaceBattleJarSupplyForecast`: read-only expected-scenario estimate with initial Warehouse, Core time Producer and finite-input Parser source separation.
- `SpaceBattleSupplyReconciliation`: Parser historical receipts and current Core Warehouse/Master/Slave account balances are displayed as separate facts.
- `SpaceJarHudObserver` and `Game.get_supply_reconciliation_snapshot()`: read-only reconciliation is already exposed in the battle HUD.
- `SpaceDomainContractProbe`: supply forecast and reconciliation probes are included in the shared domain-contract suite.

Forecasts remain estimates; Parser receipts are historical import facts; current Core account balances are live facts. Source attribution per current Jar is unavailable and must not be inferred by subtracting historical import counts from current inventory.

## 4. Progression reward integration gap

The code audit found a clear module-connection gap:

- `SpaceProgressionRewardService.prepare_settlement()` already validates source-kind/item-kind attribution, exact curve identity/version, positive final integer XP, settlement fingerprints and per-event idempotency. It prepares a detached progression candidate.
- `GameState.commit_space_progression_reward_settlement()` already persists that candidate before publishing the new player aggregate.
- `SpaceProgressionRewardServiceProbe` exercises this service with synthetic XP values only; those values are not balance data.
- `Game.gd::_try_complete_stage()` currently invokes the durable campaign-clear callback. It does not collect the battle's committed reward facts or call the XP settlement entry point.
- `SpaceHangarCatalogBundleResource` currently assembles the gameplay catalogs and effect catalog, but does not provide an authored progression reward policy / exact-version curve catalog for a production reward loop.
- `SpaceStageDefinition.completion_rewards` is currently an unconstrained Dictionary; the shipped stage assets inspected here leave it empty. Its presence in the Hangar preview does not mean an XP policy is implemented.
- Campaign clear persistence and XP progression persistence are separate aggregates/files. They must not be described as one atomic reward transaction.

### Required next contract

Before enabling XP awards in production, define a versioned Space-owned Reward Profile that declares:

1. Supported committed fact kinds and their source identity.
2. The exact Owned Instance resolution rule for each fact kind.
3. Exact Curve ID / Version for the receiving item kind.
4. Unit conversion, aggregation, rounding, caps and policy version.
5. Stable source Event ID and settlement ID rules.
6. Recovery semantics when campaign clear is durable but progression settlement is not, or vice versa.

The fact sources must be authoritative:

- Ship: accepted Pickup IDs and/or a durably committed battle objective/clear fact.
- Ore Parser: actually consumed volume or committed Parser work, not merely accepted/pending stone volume or forecast output.
- Production Device: confirmed work result from its actual runtime consumer.
- Workshop: committed Core rule-transition facts with the exact executing Workshop Owned Instance; Solver paths and MATCH alone are not work XP.
- Skill: the durable Core order-cycle event after the Space effect commit, not a button press or queued demand.

No XP amount, coefficient, curve threshold or cap is invented in this audit. The existing generic reward service continues to receive final integer XP from versioned content policy.

### Transaction boundary to resolve

Campaign clear and progression XP currently use separate durable saves. The next implementation must use an explicit recoverable outbox / pending-settlement protocol or a single coordinated persistence transaction. It must not simply call two independent save functions and claim all-or-nothing behavior. A retry must return the original result for the same event/settlement payload and reject conflicting payloads.

## 5. Next grouped implementation batch

1. Add the versioned Reward Profile and exact catalog binding without authoring arbitrary XP balance values.
2. Add a durable committed-fact envelope/outbox for the battle sources that currently lack stable reward-event receipts; include it in the coordinated battle checkpoint.
3. Wire stage/battle terminal settlement through one recoverable progression-reward coordinator; keep campaign clear and XP receipt identities distinct.
4. Add probes for duplicate delivery, conflicting event payload, missing curve, stale progression revision, save failure, restore between campaign-clear and XP commit, and retry after restart.
5. Update the module map, progression architecture, gameplay contract, work-record index and this record with exact code/validation evidence.
6. Only after the grouped batch is coherent, run the complete Core + Bridge + Space import/build/domain/runtime/lifecycle verification and then desktop GUI acceptance.

Application lifecycle work remains a separate grouped pass after the reward settlement boundary is defined. No GUI result is inferred from Headless probes.
