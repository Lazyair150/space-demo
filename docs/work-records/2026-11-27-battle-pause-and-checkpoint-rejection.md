# 2026-11-27 Battle pause discoverability and runtime checkpoint rejection

## User-observed symptoms

- Combat starts, but the player cannot discover a pause button or a Main Menu action.
- When an order effect is dispatched, `SpaceBattleEffectStateStore.save` reports: `Battle runtime checkpoint is incomplete or does not match the frozen loadout`.
- The event originates from `SpaceOrderEffectCommitter.commit`, invoked by `SpaceOrderEffectDispatcher.drain_pending` after a completed Jar step.
- A later `combat scene removed before terminal shutdown` message means the Game node was removed without its lifecycle owner first closing the battle. It is a separate teardown symptom, not the checkpoint validator's root cause.

## Pause UI root cause and correction

The scene already instanced `SpaceBattlePauseController`, but the controller only listened for Escape. It did not create an always-visible on-screen pause entry point. Its paused overlay contained only a Continue button, so there was no normal player-facing Main Menu action.

Changes:
- Add a persistent top-right `Ⅱ 暂停` button; Escape remains a shortcut.
- Paused overlay exposes Continue and Return to Main Menu.
- Add `Game.end_battle_for_menu()` as the lifecycle-owned exit: dispose World V2 host, mark the battle ended, then call `GameFlow.return_to_menu`.
- Keep a terminal retry action if the menu scene transition fails.
- Extend the pause probe to assert the visible button and both paused actions.

## Checkpoint rejection diagnosis

The old state store returned one generic error for every invalid checkpoint. The validator was expanded to identify the exact contract failure, including:
- checkpoint schema and loadout identity;
- finite-stage identity and director/objective state;
- Jar checkpoint presence;
- run score/wave/segment coherence;
- shared clock remainder range;
- parser envelope/runtime schema, pickup sequence, RNG state and pending-pickup array.

The validation remains strict. This change does not bypass persistence, acknowledge a failed Jar event, or invent defaults. It converts an opaque rejection into a precise diagnostic so the actual failing field can be corrected without weakening the frozen-loadout contract.

## Validation status

- Source changes committed to the Space PR branch.
- Headless pause probe assertions updated.
- Exact Core/Space cross-repo CI and desktop GUI verification are pending.
- The next desktop run must capture the new `[BattleStateStore] Runtime checkpoint rejected: ...` line. That exact reason determines whether the remaining checkpoint defect is a source-state capture bug or a schema-contract mismatch.
- Do not close this issue until order effects persist successfully and a desktop player can pause, resume, and return to Main Menu.


## Follow-up source audit: confirmed checkpoint schema defect

The exact rejection is now known from code and is independent of the user's desktop GPU issue:

- `Game.capture_ore_parser_state()` emits an outer Space envelope at schema 2.
- `SpaceOreParserRuntime.capture_state()` emits an inner runtime checkpoint at schema 5 (`STATE_SCHEMA_VERSION = 5`).
- `SpaceBattleEffectStateStore._runtime_checkpoint_validation_error()` incorrectly required the nested `parserRuntime.schemaVersion` to equal 2.
- Therefore a valid live Parser checkpoint could never pass the state-store validator. The old store probe also used a hand-authored `{"schemaVersion": 2}` placeholder, so it did not resemble production capture output.

Correction:
- Distinguish the outer envelope schema from nested Parser Runtime schema.
- Accept inner versions 2, 3, 4 and current 5, matching the exact versions supported by `SpaceOreParserRuntime.restore_state()`. Reject future/unknown versions with an explicit diagnostic.
- Rewrite the state-store probe to instantiate a real `SpaceOreParserRuntime`, ingest a finite stone volume, advance it, capture schema 5 state, restore it through a second runtime and persist the real captured state. Assert schema 5 is accepted, a future schema is rejected explicitly, and legacy schema 2 remains accepted by the persistence validator because the runtime migration supports it.

Sandbox boundary:
- `Game.allow_sandbox_world_for_development` previously defaulted to true, which contradicted the development guide's rule that Sandbox initialization is opt-in for isolated development probes.
- Its default is now false. Production launch remains Hangar-owned and must supply a frozen Owned Loadout.

The earlier user report's uncommitted local `project.godot` change cannot be inspected from the GitHub checkout. The remote branch currently contains the explicit Windows Vulkan setting and preserves the Mobile rendering method. Do not overwrite a dirty local file until its diff is inspected; compare with `git diff -- project.godot` before deciding whether to discard or keep local edits.

## Validation still outstanding

The cross-repo CI must run the strengthened StateStore probe and World V2 integration suite. This fixes a deterministic code-level validator mismatch but does not itself prove real Windows disk writes, crash recovery, Jar/Core restore and desktop resume. Desktop acceptance must exercise a real order effect, verify durable save success/no rejection line, exit/relaunch, restore, and confirm event idempotency.


## Final CI result for the checkpoint/schema correction

- Branch HEAD tested: `fc87d331fbb8361f20f66b0241a1735ba325dd9d`.
- Cross-repository workflow Run `45942323918`: **completed / success**.
- Exact Core PR #63 SHA: `116c0bb7e3589a2850bf1b85f6da4c48de8c0a28`.
- Core Bridge and Space .NET builds succeeded; Godot 4.7.1 project import and GDScript parsing succeeded.
- `SpaceDomainContractProbe`: `battle-effect-state-store=passed`, `battle-reward-fact-projection=passed`, `all-domain-contracts=passed`.
- Final integration marker: `CROSS-REPO-WORLD-V2-OK`.
- The StateStore log contains the deliberate negative-input rejection cases (empty Jar checkpoint, absent RNG state, wave/segment mismatch, missing runState); the probe itself reports success after asserting these invalid states were rejected and the last valid snapshot retained. They are not unhandled production errors.
- Run link: https://github.com/Lazyair150/space-demo/actions/runs/45942323918

## Repository UID sidecar audit

The current remote tree contains 171 GDScript files and 155 tracked `.gd.uid` sidecars. The following 17 scripts do not yet have tracked sidecars in this branch:

- `scripts/industrial/world_v2/SpaceBattleJarSupplyForecast.gd`
- `scripts/industrial/world_v2/SpaceBattleJarSupplyForecastProbe.gd`
- `scripts/industrial/world_v2/SpaceBattlePauseProbeOwner.gd`
- `scripts/industrial/world_v2/SpaceBattleRewardFactProjection.gd`
- `scripts/industrial/world_v2/SpaceBattleRewardFactProjectionProbe.gd`
- `scripts/industrial/world_v2/SpaceBattleSupplyReconciliation.gd`
- `scripts/industrial/world_v2/SpaceBattleSupplyReconciliationProbe.gd`
- `scripts/industrial/world_v2/SpaceBattleSupplyScenarioProfile.gd`
- `scripts/industrial/world_v2/SpaceDemoProgressionBootstrapProbe.gd`
- `scripts/industrial/world_v2/SpaceDomainContractProbe.gd`
- `scripts/industrial/world_v2/SpaceProgressionRewardCoordinator.gd`
- `scripts/industrial/world_v2/SpaceProgressionRewardCoordinatorProbe.gd`
- `scripts/industrial/world_v2/SpaceProgressionRewardProfile.gd`
- `scripts/industrial/world_v2/SpaceProgressionRewardProfileProbe.gd`
- `scripts/industrial/world_v2/SpaceProgressionRewardService.gd`
- `scripts/industrial/world_v2/SpaceProgressionRewardServiceProbe.gd`
- `tests/space_hangar_contracts.gd`

These sidecar contents must come from the user's existing local Godot-generated files; they must not be fabricated or regenerated independently on GitHub. After syncing, compare the local untracked UID names to this list, stage the actual generated sidecars, inspect them, and commit them. Do not add `.uid` to `.gitignore`.
