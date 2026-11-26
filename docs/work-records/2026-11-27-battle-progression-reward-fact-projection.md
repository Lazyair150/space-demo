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
- The previous exact integration Run `45872350494` validates the Reward Profile/service batch only; it does not include this new projection commit.
- The new code requires a new exact-head cross-repository run. Desktop GUI acceptance remains separate.
