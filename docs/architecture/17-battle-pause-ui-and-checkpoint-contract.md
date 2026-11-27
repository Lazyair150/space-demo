# Battle Pause UI and Runtime Checkpoint Contract

## Responsibilities

- `Game.gd` owns the battle lifecycle, World V2 host, and coordinated runtime checkpoint capture.
- `SpaceBattlePauseController.gd` owns player-facing pause presentation and pause input. It must not directly mutate Jar internals.
- `GameFlow.gd` owns application screen and battle-phase transitions.
- `SpaceOrderEffectCommitter.gd` commits one Space effect together with the dispatcher ledger and a coordinated runtime checkpoint.
- `SpaceBattleEffectStateStore.gd` validates and atomically replaces the combined snapshot. It must reject malformed/incompatible checkpoints, but report the exact rejected field.

## Player-facing pause contract

The combat scene includes a persistent top-right `Ⅱ 暂停` button. Escape is a keyboard shortcut, not the only entry point. The controller is `PROCESS_MODE_ALWAYS`, so it can render and receive input while gameplay is paused.

When paused, the overlay must expose two separate actions:

1. Continue: transition `PAUSED → RUNNING`, release SceneTree pause, then resume the Jar host.
2. Return to Main Menu: ask the Game lifecycle owner to terminate the battle, dispose the Jar host, transition `PAUSED → ENDED`, then use `GameFlow.return_to_menu`.

A menu transition must never bypass the Game owner and leave an active World V2 host behind. Faulted battles expose a terminal Main Menu retry action, never Resume.

## Runtime checkpoint contract

Every order-effect commit persists effect state and Dispatcher EventId atomically. A complete runtime checkpoint is attached only when it can be captured coherently. During a finite-stage active beat, the effect may be applied once in memory, but the Jar outbox event remains pending until an enemy-free inter-beat checkpoint can be saved. Never acknowledge the event or replace a valid checkpoint with a partial one. Its identity must equal the frozen loadout identity:

- `shipWorldId`
- `loadoutId`
- `loadoutVersion`
- `loadoutFingerprint`

The checkpoint contains the Jar execution checkpoint, shared clock remainder, parser runtime and pending pickups, run score/wave/segment, and optional finite-stage director/objective state. The checkpoint schema is 2 for free combat and 3 for finite stages.

The state store validates all required fields before committing. The outer Space Parser envelope is schema 2; its nested `parserRuntime` has an independent schema version. The store must accept only nested versions supported by `SpaceOreParserRuntime.restore_state` (currently 2/3/4/5), and must not confuse the outer envelope version with the nested runtime version. A rejection must identify the exact field and expected type/range; a generic “incomplete checkpoint” message is not sufficient for debugging. Rejection leaves the Jar outbox event pending and must not acknowledge it or silently continue as if it were persisted. An empty checkpoint from an active finite-stage beat is an expected deferral, not a fault. Death is terminal: close the World instance and do not request a resumable checkpoint.

## Verification gates

The pause probe must verify:
- A visible pause button exists while RUNNING.
- Pause hides the entry button and exposes Continue plus Main Menu.
- Continue restores the visible entry button and RUNNING phase.
- Focus loss pauses; focus regain does not auto-resume.
- Fault state hides the pause entry and exposes terminal navigation.

Checkpoint tests must cover both schema 2 and schema 3, malformed field diagnostics, exact frozen-loadout identity matching, and the no-acknowledgement behavior on failed durable commit.

Headless probes verify lifecycle semantics, not visual usability. Desktop acceptance must also confirm the button is visible at normal window size and the Main Menu action returns to a usable menu without stale pause state.
