# 2026-11-27 GameOver input failure and full application-flow design

## User-visible failure

The desktop screenshot shows GAME OVER and two visible buttons, but neither button responds. This is a P1 flow failure: death reaches the terminal scene, but the player cannot leave it.

## Root cause

In `scenes/menus/GameOver.tscn`, the centered VBoxContainer was only 40 px wide (`offset_left=-20`, `offset_right=20`) while its child buttons rendered much wider. The visible button surfaces extended outside their parent Control's hit-test rectangle. The full-screen ColorRect also retained its default mouse filter, allowing decorative UI to participate in pointer hit-testing.

This is why the buttons could look correct while pointer input was not reliably delivered.

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
