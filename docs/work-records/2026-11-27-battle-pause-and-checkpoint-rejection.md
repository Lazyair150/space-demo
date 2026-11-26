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
