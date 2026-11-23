extends Node

signal score_changed(new_score: int)
signal wave_changed(new_wave: int)
signal player_hp_changed(hp: int)
signal game_over_requested
signal space_progression_state_changed(state: SpacePlayerProgressionState)
signal segment_changed(label: String, wave: int)

const SAVE_PATH := "user://highscore.cfg"
const SPACE_PROGRESSION_SAVE_PATH := "user://space_progression.cfg"

var score: int = 0
var wave: int = 0
var segment: String = ""
var high_score: int = 0
var space_progression_state: SpacePlayerProgressionState

func _ready() -> void:
	_load_high_score()
	_load_space_progression_state()

func _load_high_score() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_score = int(cfg.get_value("score", "high", 0))

func reset_run() -> void:
	score = 0
	wave = 0
	segment = ""
	score_changed.emit(score)
	wave_changed.emit(wave)
	segment_changed.emit(segment, wave)

## Transient Space run state is captured with the coordinated battle checkpoint.
func capture_run_state() -> Dictionary:
	return {
		"schemaVersion": 1,
		"score": score,
		"wave": wave,
		"segment": segment
	}

func restore_run_state(state: Dictionary) -> bool:
	if int(state.get("schemaVersion", 0)) != 1:
		return false
	var raw_score: Variant = state.get("score", null)
	var raw_wave: Variant = state.get("wave", null)
	var raw_segment: Variant = state.get("segment", null)
	if typeof(raw_score) != TYPE_INT or int(raw_score) < 0:
		return false
	if typeof(raw_wave) != TYPE_INT or int(raw_wave) < 0:
		return false
	if typeof(raw_segment) != TYPE_STRING or not ["", "热身", "压力", "精英", "喘息"].has(String(raw_segment)):
		return false
	var wave_value := int(raw_wave)
	var segment_value := String(raw_segment)
	if wave_value == 0:
		if not segment_value.is_empty():
			return false
	else:
		var expected_segments := ["热身", "压力", "精英", "喘息"]
		if segment_value != String(expected_segments[(wave_value - 1) % expected_segments.size()]):
			return false
	score = int(raw_score)
	wave = wave_value
	segment = segment_value
	score_changed.emit(score)
	wave_changed.emit(wave)
	segment_changed.emit(segment, wave)
	return true

func set_segment(label: String) -> void:
	segment = label
	segment_changed.emit(segment, wave)

func report_player_hp(hp: int) -> void:
	player_hp_changed.emit(hp)

func add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)

func set_wave(new_wave: int) -> void:
	wave = new_wave
	wave_changed.emit(wave)

func report_game_over() -> void:
	if score > high_score:
		high_score = score
		_save_high_score()
	game_over_requested.emit()

func _save_high_score() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("score", "high", high_score)
	cfg.save(SAVE_PATH)

func set_space_progression_state(state: SpacePlayerProgressionState) -> bool:
	if state == null or not state.get_validation_errors().is_empty():
		return false
	if space_progression_state != null and space_progression_state.progression_changed.is_connected(_on_space_progression_changed):
		space_progression_state.progression_changed.disconnect(_on_space_progression_changed)
	space_progression_state = state
	space_progression_state.progression_changed.connect(_on_space_progression_changed)
	space_progression_state_changed.emit(space_progression_state)
	return _save_space_progression_state()

func _load_space_progression_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SPACE_PROGRESSION_SAVE_PATH) != OK:
		return
	var raw: Variant = cfg.get_value("progression", "state", null)
	if not (raw is Dictionary):
		push_warning("Space progression save is missing or malformed; no owned Hangar inventory is available")
		return
	var restored := SpacePlayerProgressionState.from_data(raw)
	if restored == null:
		push_error("Space progression save failed schema/ownership validation")
		return
	space_progression_state = restored
	space_progression_state.progression_changed.connect(_on_space_progression_changed)
	space_progression_state_changed.emit(space_progression_state)

func _on_space_progression_changed(_revision: int) -> void:
	_save_space_progression_state()

func _save_space_progression_state() -> bool:
	if space_progression_state == null or not space_progression_state.get_validation_errors().is_empty():
		return false
	var cfg := ConfigFile.new()
	cfg.set_value("progression", "state", space_progression_state.to_data())
	return cfg.save(SPACE_PROGRESSION_SAVE_PATH) == OK
