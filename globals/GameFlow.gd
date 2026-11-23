extends Node
## Central application/simulation state registry. Scene loading remains owned by the
## current screen/launcher; this node validates and broadcasts lifecycle transitions.

signal state_changed(snapshot: Dictionary)

enum Screen { MENU, HANGAR, INDUSTRIAL, BATTLE, GAME_OVER }
enum BattlePhase { INACTIVE, PREPARING, RUNNING, PAUSED, RESUMING, ENDED, FAULTED }
enum PauseReason { NONE, PLAYER, WINDOW_FOCUS_LOST, SYSTEM }

var _screen: int = Screen.MENU
var _battle_phase: int = BattlePhase.INACTIVE
var _pause_reason: int = PauseReason.NONE
var _transition_sequence: int = 0

func snapshot() -> Dictionary:
	return {
		"schemaVersion": 1,
		"screen": Screen.keys()[_screen],
		"battlePhase": BattlePhase.keys()[_battle_phase],
		"pauseReason": PauseReason.keys()[_pause_reason],
		"transitionSequence": _transition_sequence
	}

func enter_screen(next_screen: int) -> bool:
	if next_screen < 0 or next_screen >= Screen.keys().size():
		return false
	if _battle_phase in [BattlePhase.PREPARING, BattlePhase.RUNNING, BattlePhase.PAUSED, BattlePhase.RESUMING] and next_screen != Screen.BATTLE:
		push_error("[GameFlow] Cannot leave an active battle before it is ended")
		return false
	if next_screen == Screen.BATTLE:
		return begin_battle_preparation()
	if next_screen == Screen.GAME_OVER and not (_battle_phase in [BattlePhase.ENDED, BattlePhase.FAULTED]):
		push_error("[GameFlow] GameOver requires an ended or faulted battle")
		return false
	_screen = next_screen
	_emit_state()
	return true

func begin_battle_preparation() -> bool:
	if _battle_phase in [BattlePhase.PREPARING, BattlePhase.RUNNING, BattlePhase.PAUSED, BattlePhase.RESUMING]:
		return _screen == Screen.BATTLE
	_battle_phase = BattlePhase.PREPARING
	_pause_reason = PauseReason.NONE
	_screen = Screen.BATTLE
	_emit_state()
	return true

func mark_battle_running() -> bool:
	if not (_battle_phase in [BattlePhase.PREPARING, BattlePhase.RESUMING]):
		return false
	_battle_phase = BattlePhase.RUNNING
	_pause_reason = PauseReason.NONE
	_emit_state()
	return true

func pause_battle(reason: int = PauseReason.PLAYER) -> bool:
	if _screen != Screen.BATTLE or _battle_phase != BattlePhase.RUNNING or reason <= PauseReason.NONE or reason >= PauseReason.size():
		return false
	_battle_phase = BattlePhase.PAUSED
	_pause_reason = reason
	_emit_state()
	return true

func resume_battle() -> bool:
	if _screen != Screen.BATTLE or _battle_phase != BattlePhase.PAUSED:
		return false
	_battle_phase = BattlePhase.RUNNING
	_pause_reason = PauseReason.NONE
	_emit_state()
	return true

func end_battle() -> bool:
	if _battle_phase in [BattlePhase.INACTIVE, BattlePhase.ENDED, BattlePhase.FAULTED]:
		return false
	_battle_phase = BattlePhase.ENDED
	_pause_reason = PauseReason.NONE
	_emit_state()
	return true

func fault_battle() -> bool:
	if _battle_phase in [BattlePhase.INACTIVE, BattlePhase.ENDED, BattlePhase.FAULTED]:
		return false
	_battle_phase = BattlePhase.FAULTED
	_pause_reason = PauseReason.NONE
	_emit_state()
	return true

func _emit_state() -> void:
	_transition_sequence += 1
	state_changed.emit(snapshot())