extends RefCounted
class_name SpaceStageEncounterDirector
## Deterministic finite-beat mission state. It schedules authored beats; Spawner owns actors.

enum State { READY, ACTIVE, COMPLETE, FAULTED }

var _stage: SpaceStageDefinition
var _state: int = State.READY
var _next_beat_index: int = 0
var _difficulty_profile: Dictionary = {}

func configure(stage: SpaceStageDefinition, frozen_loadout_data: Dictionary) -> bool:
	if _state != State.READY or _stage != null or stage == null or not stage.is_valid():
		return false
	var profile := SpaceStageProgressionProfile.evaluate(stage, frozen_loadout_data)
	if not bool(profile.get("valid", false)):
		return false
	_stage = stage
	_difficulty_profile = profile.duplicate(true)
	return true

func begin() -> Dictionary:
	if _stage == null or _state != State.READY:
		return {}
	_state = State.ACTIVE
	return current_beat()

func current_beat() -> Dictionary:
	if _stage == null or _state != State.ACTIVE or _next_beat_index < 0 or _next_beat_index >= _stage.wave_count():
		return {}
	var beat := _stage.wave_plan(_next_beat_index + 1)
	beat["beatIndex"] = _next_beat_index
	beat["difficultyProfile"] = _difficulty_profile.duplicate(true)
	return beat

func complete_current_beat() -> Dictionary:
	if _state != State.ACTIVE or _stage == null:
		return {"success": false, "complete": false}
	_next_beat_index += 1
	if _next_beat_index >= _stage.wave_count():
		_state = State.COMPLETE
		return {"success": true, "complete": true, "stageId": String(_stage.stage_id), "definitionVersion": _stage.definition_version}
	return {"success": true, "complete": false, "nextBeat": current_beat()}

func capture_state() -> Dictionary:
	if _stage == null:
		return {}
	return {
		"schemaVersion": 1,
		"stageId": String(_stage.stage_id),
		"definitionVersion": _stage.definition_version,
		"state": _state,
		"nextBeatIndex": _next_beat_index,
		"difficultyProfile": _difficulty_profile.duplicate(true)
	}

func restore_state(stage: SpaceStageDefinition, frozen_loadout_data: Dictionary, source: Dictionary) -> bool:
	if _state != State.READY or _stage != null or stage == null or not stage.is_valid() or int(source.get("schemaVersion", 0)) != 1:
		return false
	if String(source.get("stageId", "")) != String(stage.stage_id) or int(source.get("definitionVersion", 0)) != stage.definition_version:
		return false
	var saved_state: Variant = source.get("state", null)
	var beat_index: Variant = source.get("nextBeatIndex", null)
	if typeof(saved_state) != TYPE_INT or int(saved_state) not in [State.READY, State.ACTIVE, State.COMPLETE] or typeof(beat_index) != TYPE_INT or int(beat_index) < 0 or int(beat_index) > stage.wave_count():
		return false
	var expected := SpaceStageProgressionProfile.evaluate(stage, frozen_loadout_data)
	var saved_profile: Variant = source.get("difficultyProfile", null)
	if not bool(expected.get("valid", false)) or not (saved_profile is Dictionary) or saved_profile != expected:
		return false
	if int(saved_state) == State.READY and int(beat_index) != 0:
		return false
	if int(saved_state) == State.COMPLETE and int(beat_index) != stage.wave_count():
		return false
	if int(saved_state) != State.COMPLETE and int(beat_index) >= stage.wave_count() and int(saved_state) != State.READY:
		return false
	_stage = stage
	_state = int(saved_state)
	_next_beat_index = int(beat_index)
	_difficulty_profile = expected
	return true

func state() -> int:
	return _state

func stage_identity() -> Dictionary:
	if _stage == null:
		return {}
	return {"stageId": String(_stage.stage_id), "definitionVersion": _stage.definition_version}
