extends Node
## Authoritative application navigation and simulation lifecycle owner.
## Screen owners request transitions; only this node calls change_scene_to_file.

signal state_changed(snapshot: Dictionary)
signal transition_failed(target_screen: int, scene_path: String, error_code: int)

enum Screen { MENU, HANGAR, INDUSTRIAL, BATTLE, GAME_OVER }
enum BattlePhase { INACTIVE, PREPARING, RUNNING, PAUSED, RESUMING, RESUME_READY, ENDED, FAULTED }
enum PauseReason { NONE, PLAYER, WINDOW_FOCUS_LOST, SYSTEM }

var _screen: int = Screen.MENU
var _battle_phase: int = BattlePhase.INACTIVE
var _pause_reason: int = PauseReason.NONE
var _transition_sequence: int = 0

func snapshot() -> Dictionary:
	return {
		"schemaVersion": 3,
		"screen": Screen.keys()[_screen],
		"battlePhase": BattlePhase.keys()[_battle_phase],
		"pauseReason": PauseReason.keys()[_pause_reason],
		"transitionSequence": _transition_sequence
	}

func request_scene_transition(next_screen: int, scene_path: String) -> bool:
	if scene_path.is_empty() or next_screen < 0 or next_screen >= Screen.keys().size():
		return false
	var previous_screen := _screen
	var previous_phase := _battle_phase
	var previous_reason := _pause_reason
	if not enter_screen(next_screen):
		return false
	var error_code := get_tree().change_scene_to_file(scene_path)
	if error_code == OK:
		return true
	_screen = previous_screen
	_battle_phase = previous_phase
	_pause_reason = previous_reason
	_emit_state()
	transition_failed.emit(next_screen, scene_path, error_code)
	push_error("[GameFlow] Scene transition failed (%d): %s" % [error_code, scene_path])
	return false

func enter_screen(next_screen: int) -> bool:
	if next_screen < 0 or next_screen >= Screen.keys().size():
		return false
	if _battle_phase in [BattlePhase.PREPARING, BattlePhase.RUNNING, BattlePhase.PAUSED, BattlePhase.RESUMING, BattlePhase.RESUME_READY] and next_screen != Screen.BATTLE:
		push_error("[GameFlow] Cannot leave an active battle before it has ended")
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
	# Re-entry is idempotent only while the same launch is still preparing.
	# A second scene must never replace a live/paused/resuming battle.
	if _battle_phase == BattlePhase.PREPARING:
		return _screen == Screen.BATTLE
	if _battle_phase in [BattlePhase.RUNNING, BattlePhase.PAUSED, BattlePhase.RESUMING, BattlePhase.RESUME_READY]:
		return false
	_battle_phase = BattlePhase.PREPARING
	_pause_reason = PauseReason.NONE
	_screen = Screen.BATTLE
	_emit_state()
	return true

func begin_battle_resuming() -> bool:
	if _screen != Screen.BATTLE or _battle_phase != BattlePhase.PREPARING:
		return false
	_battle_phase = BattlePhase.RESUMING
	_pause_reason = PauseReason.NONE
	_emit_state()
	return true

func mark_battle_resume_ready() -> bool:
	if _screen != Screen.BATTLE or _battle_phase != BattlePhase.RESUMING:
		return false
	_battle_phase = BattlePhase.RESUME_READY
	_pause_reason = PauseReason.SYSTEM
	_emit_state()
	return true

func confirm_resume_battle() -> bool:
	if _screen != Screen.BATTLE or _battle_phase != BattlePhase.RESUME_READY:
		return false
	_battle_phase = BattlePhase.RUNNING
	_pause_reason = PauseReason.NONE
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
