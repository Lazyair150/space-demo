# 2026-11-27 GameOver input failure and full application-flow design

## User-visible failure

The desktop screenshot shows GAME OVER and two visible buttons, but neither button responds. This is a P1 flow failure: death reaches the terminal scene, but the player cannot leave it.

## Root cause

In `scenes/menus/GameOver.tscn`, the centered VBoxContainer was only 40 px wide (`offset_left=-20`, `offset_right=20`) while its child buttons rendered much wider. The visible button surfaces extended outside their parent Control's hit-test rectangle. The full-screen ColorRect also retained its default mouse filter, allowing decorative UI to participate in pointer hit-testing.

This is why the buttons could look correct while pointer input was not reliably delivered. A source audit found the same 40×40 centered-container pattern in MainMenu, so that screen was corrected in the same batch rather than leaving the startup route broken. Hangar's full-screen decorative ColorRect was also set to ignore pointer input.

## Corrections committed

- Expanded the VBoxContainer to a 420×290 interactive rectangle around all visible controls.
- Set the full-screen background ColorRect to `MOUSE_FILTER_IGNORE`.
- Set GameOver root to `PROCESS_MODE_ALWAYS`.
- Set explicit button minimum sizes and keyboard focus.
- Disable duplicate navigation clicks while a transition is in flight and restore buttons if the transition is rejected.

## Order-effect checkpoint deferral

The source confirms the finite-stage checkpoint guard is intentional: Spawner only permits resumable checkpoints during an enemy-free inter-beat window. The order-effect committer, however, attempted to capture a resumable checkpoint on every Jar outbox event. During an active beat the provider returned an empty Dictionary and emitted a warning/error every physics frame.

Correction:
- Empty runtime checkpoint during an active finite-stage beat is treated as expected deferral.
- The effect is applied once in memory through the manager's processed-event idempotency.
- The dispatcher leaves the Jar event pending until a coherent checkpoint is available; it acknowledges only after durable commit.
- No partial checkpoint is written and the strict persistence validator is not weakened.

Death is terminal and closes the World instance; it must not depend on a resumable inter-beat checkpoint.

## Application UI architecture

Added a full lifecycle model with:
- one application director (`GameFlow`);
- root screens distinct from battle phases and overlays;
- explicit directed routes and transition guards;
- battle owner (`Game.gd`) responsible for Host disposal;
- pause/fault/game-over/exit semantics;
- Godot Control hit-testing, process mode, focus and mouse-filter rules;
- automated and desktop acceptance matrix.

## Open-source review

Reviewed Godot official docs for Control input propagation and pause process modes, plus GState, Scene Manager, Scenic and GodotSceneManager. Decision: retain the existing project-owned GameFlow director. Do not add a plugin that would duplicate state authority or bypass native SceneTree ownership. Re-evaluate only if transition animation/loading becomes a concrete requirement.

## Validation status

- Source fixes and architecture/work-record documentation are committed.
- No exact-head Godot editor import, cross-repository verification or desktop click test has yet been run for these changes.
- User must verify GameOver mouse clicks and keyboard focus on the next desktop build; a headless probe cannot prove actual pointer usability.

## Commit ledger

- GameOver scene hit-test bounds and background mouse filter: `1d35773a697a2054fe4001a25faee2569b0d0a31`, then container bounds correction: `291f843279eb36648adbcb42c5ce91695856bd09`.
- Finite-stage checkpoint deferral without repeated warning/error: `d4b373b5f94fcd1a2101b1387f9f3c59ddaaa5e8` and `4fb306b593c7ffe86922ea180e74aeea02c5ba9f`.
- GameOver action guards and runtime hit-test geometry diagnostic: `3111452ab6e9a667cd1618b0d8046f3dcca1f4a6`, `6d0508eef2499cbc938abb14cd86185628673f68`.
- Application flow architecture: `1eb5896730564d0be5fe5921f895903943ee0df4`; external references: `8a08c49fa575bc88f62c320e34be26f5c3feeaa4`.
- Development guide/work-record index synchronization: `b5860bc3f0c83e4c76439a7636a8da6d6e8654e3`, `9c2f51512c206217f35934f08367fe0c01979696`.
- Exact Space PR #2 head before this final work-record update: `8a08c49fa575bc88f62c320e34be26f5c3feeaa4`; this record update produces the next head.

The commits above are code/document changes, not test evidence. Exact-head CI, Godot editor import, cross-repository verification and desktop pointer tests remain pending.


### Startup and Hangar UI audit additions

- MainMenu root and VBoxContainer were corrected; Start/Quit buttons receive explicit size/focus and runtime geometry validation. MainMenu actions now disable duplicate clicks and restore controls on rejected navigation.
- Hangar's decorative background ColorRect now uses `MOUSE_FILTER_IGNORE`, so it cannot compete with interactive content.
- These are additive presentation/input corrections; no combat rules or frozen loadout data are changed.

- Startup-route audit additions: MainMenu scene bounds/background filter `7d60a581a81a62f46d06cc5bbf4479d1b2fe89ea`; MainMenu actions and runtime geometry check `f1ed8f1485358a1d0768c14838ee3d0ebdd1556e`; Hangar background pointer filter `019c93686fc34c83e18035ec0115b48382c682fe`.
- Architecture/work-record audit update commits: `cbd57affda7c756491f42d77109a531ec69cb9f5`, `8f2520d7ebdd295130d67f0675a6c7192c6dbbc8`.
