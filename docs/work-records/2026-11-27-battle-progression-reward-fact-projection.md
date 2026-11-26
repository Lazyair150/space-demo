# 2026-11-27 Battle progression reward fact projection

## Baseline

- Space branch: `world-v2/phase-4.10b-hangar-ui`
- Starting HEAD: `f878272b0d31af9653bc76a8e26421fb83f89994`
- Core exact pin: `116c0bb7e3589a2850bf1b85f6da4c48de8c0a28`
- Previous exact integration: Run `45872350494` SUCCESS on Space code HEAD `068d89f0` and Core `116c0bb7`.

## Changes

Added `SpaceBattleRewardFactProjection.gd` and its domain probe.

The projection reads only:
- The frozen loadout's exact Ship Owned Instance and Ore Parser Owned Instance.
- The Parser runtime's accepted Pickup identity ledger (`seenPickups`) from the coordinated Parser checkpoint.
- The exact objective-complete Stage identity supplied by the battle terminal path.

It emits stable facts for:
- Each accepted Energy Stone Pickup, attributed to the frozen Ship Instance and keyed by Pickup ID.
- The finite Stage objective completion, attributed to the same Ship Instance and keyed by Ship World ID + Stage ID + Definition Version.

The Stage reward settlement ID is deterministic: `space-stage-reward:<shipWorldId>:<stageId>@<version>`.

`Game._try_complete_stage()` now projects this envelope before invoking the existing durable campaign-clear callback. The callback already persists the complete result Dictionary inside `SpaceCampaignProgressState`; therefore the Stage clear record now durably stores the reward settlement identity and committed-fact envelope together with the clear fact. If the callback fails, neither the campaign clear nor its fact envelope is published.

## Explicit coverage limits

This is the first source adapter, not a claim that all battle XP sources are wired.

Not yet projected:
- Parser actual processed volume / completed processing work.
- Production Device committed work.
- Core Workshop rule-transition receipts with exact Master/Slave Owned Instance attribution.
- Core OrderCycleCompleted -> Skill effect commit facts.

The projection reports these source kinds as not yet captured. It does not infer them from accepted stone volume, Parser forecasts, Solver candidates, UI activations or current inventory balances.

## Settlement boundary retained

- The campaign clear record now acts as a durable source-fact outbox.
- XP application remains a separate progression aggregate and is not called by this projection.
- The next coordinator must consume the outbox idempotently and mark/recognize completion without assuming campaign and progression saves are one atomic write.
- No XP balance values or unit conversion coefficients were added.

## Validation status

- Added `battle-reward-fact-projection` to `SpaceDomainContractProbe`.
- The probe covers exact Ship attribution, stable Pickup/Stage event identity, deterministic ordering, failed-stage rejection, Parser identity mismatch and explicit unimplemented source coverage.
- Exact cross-repository Run `45873311127` completed SUCCESS on Space code HEAD `82d5cbdd72138de40e8e7e932e407121d94b99f2` and Core pin `116c0bb7e3589a2850bf1b85f6da4c48de8c0a28`.
- Both .NET builds succeeded; Godot 4.7.1 import/parse, HUD feedback, battle reward fact projection, Reward Profile, reward settlement, all domain contracts, Parser/Core ingress, runtime, lifecycle, fault, disposed/faulted commands, snapshot isolation and battle-navigation probes passed.
- Desktop GUI acceptance remains separate.


## Exact integration evidence

- [Space Run 45873311127](https://github.com/Lazyair150/space-demo/actions/runs/45873311127): SUCCESS.
- Log markers: `battle-reward-fact-projection=passed`, `progression-reward-profile=passed`, `progression-reward-settlement=passed`, `all-domain-contracts=passed`, `CROSS-REPO-WORLD-V2-OK core=116c0bb7...`.
- No desktop GUI result is inferred from this headless workflow.
