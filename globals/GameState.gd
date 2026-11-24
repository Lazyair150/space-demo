extends Node

signal score_changed(new_score: int)
signal wave_changed(new_wave: int)
signal player_hp_changed(hp: int)
signal game_over_requested
signal space_progression_state_changed(state: SpacePlayerProgressionState)
signal space_campaign_progress_changed(state: SpaceCampaignProgressState)
signal segment_changed(label: String, wave: int)

const SAVE_PATH := "user://highscore.cfg"
const SPACE_PROGRESSION_SAVE_PATH := "user://space_progression.cfg"
const SPACE_CAMPAIGN_SAVE_PATH := "user://space_campaign_progress.cfg"

var score: int = 0
var wave: int = 0
var segment: String = ""
var high_score: int = 0
var space_progression_state: SpacePlayerProgressionState
var space_campaign_progress_state: SpaceCampaignProgressState

func _ready() -> void:
	_load_high_score()
	_load_space_progression_state()
	_load_space_campaign_progress_state()

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
	var candidate := SpacePlayerProgressionState.from_data(state.to_data())
	if candidate == null or not _save_progression_candidate(candidate):
		return false
	if space_progression_state != null and space_progression_state.progression_changed.is_connected(_on_space_progression_changed):
		space_progression_state.progression_changed.disconnect(_on_space_progression_changed)
	space_progression_state = candidate
	space_progression_state.progression_changed.connect(_on_space_progression_changed)
	space_progression_state_changed.emit(space_progression_state)
	return true

## Reward acquisition is committed on a detached aggregate and persisted before publication.
func acquire_space_reward_instance(
	expected_state: SpacePlayerProgressionState,
	instance: SpaceOwnedProgressionInstance,
	reward_id: String
) -> bool:
	if expected_state == null or expected_state != space_progression_state or instance == null or reward_id.strip_edges().is_empty():
		return false
	var candidate := SpacePlayerProgressionState.from_data(space_progression_state.to_data())
	if candidate == null or not candidate.unlock_and_acquire_instance(instance, reward_id):
		return false
	if not _save_progression_candidate(candidate):
		push_error("Roguelike reward acquisition was rejected because the progression save failed")
		return false
	if space_progression_state.progression_changed.is_connected(_on_space_progression_changed):
		space_progression_state.progression_changed.disconnect(_on_space_progression_changed)
	space_progression_state = candidate
	space_progression_state.progression_changed.connect(_on_space_progression_changed)
	space_progression_state_changed.emit(space_progression_state)
	return true

func _load_space_progression_state() -> void:
	var cfg := ConfigFile.new()
	var load_result := cfg.load(SPACE_PROGRESSION_SAVE_PATH)
	var backup_path := SPACE_PROGRESSION_SAVE_PATH + ".previous"
	if load_result != OK and FileAccess.file_exists(backup_path):
		var backup_cfg := ConfigFile.new()
		if backup_cfg.load(backup_path) == OK:
			var absolute_target := ProjectSettings.globalize_path(SPACE_PROGRESSION_SAVE_PATH)
			var absolute_backup := ProjectSettings.globalize_path(backup_path)
			if FileAccess.file_exists(SPACE_PROGRESSION_SAVE_PATH):
				DirAccess.remove_absolute(absolute_target)
			if DirAccess.rename_absolute(absolute_backup, absolute_target) == OK:
				cfg = backup_cfg
				load_result = OK
	if load_result != OK:
		return
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
	var pending_path := SPACE_PROGRESSION_SAVE_PATH + ".pending"
	if FileAccess.file_exists(pending_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pending_path))
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

func record_space_stage_clear(stage: SpaceStageDefinition, result: Dictionary, settlement_id: String) -> bool:
	if stage == null or result.is_empty() or settlement_id.strip_edges().is_empty():
		return false
	var candidate := SpaceCampaignProgressState.from_data(
		space_campaign_progress_state.to_data()
	) if space_campaign_progress_state != null else SpaceCampaignProgressState.new()
	if candidate == null or not candidate.record_stage_clear(stage, result, settlement_id):
		return false
	# Persist the detached candidate before publishing it. A disk failure must not
	# mutate the live unlock ledger or make a retry look like a duplicate clear.
	if not _save_campaign_progress_candidate(candidate):
		push_error("Campaign stage clear was not committed because its durable save failed")
		return false
	if space_campaign_progress_state != null and space_campaign_progress_state.campaign_progress_changed.is_connected(_on_space_campaign_progress_changed):
		space_campaign_progress_state.campaign_progress_changed.disconnect(_on_space_campaign_progress_changed)
	space_campaign_progress_state = candidate
	space_campaign_progress_state.campaign_progress_changed.connect(_on_space_campaign_progress_changed)
	space_campaign_progress_changed.emit(space_campaign_progress_state)
	return true

func _load_space_campaign_progress_state() -> void:
	var cfg := ConfigFile.new()
	var load_result := cfg.load(SPACE_CAMPAIGN_SAVE_PATH)
	var backup_path := SPACE_CAMPAIGN_SAVE_PATH + ".previous"
	if load_result != OK and FileAccess.file_exists(backup_path):
		var backup_cfg := ConfigFile.new()
		if backup_cfg.load(backup_path) == OK:
			var absolute_target := ProjectSettings.globalize_path(SPACE_CAMPAIGN_SAVE_PATH)
			var absolute_backup := ProjectSettings.globalize_path(backup_path)
			if FileAccess.file_exists(SPACE_CAMPAIGN_SAVE_PATH):
				DirAccess.remove_absolute(absolute_target)
			if DirAccess.rename_absolute(absolute_backup, absolute_target) == OK:
				cfg = backup_cfg
				load_result = OK
	if load_result == OK and FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
	var pending_path := SPACE_CAMPAIGN_SAVE_PATH + ".pending"
	if FileAccess.file_exists(pending_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pending_path))
	if load_result != OK:
		space_campaign_progress_state = SpaceCampaignProgressState.new()
	else:
		var raw: Variant = cfg.get_value("campaign", "state", null)
		if not (raw is Dictionary):
			push_warning("Space campaign progress save is missing or malformed; campaign clears start empty")
			space_campaign_progress_state = SpaceCampaignProgressState.new()
		else:
			space_campaign_progress_state = SpaceCampaignProgressState.from_data(raw)
			if space_campaign_progress_state == null:
				push_error("Space campaign progress save failed schema validation")
				space_campaign_progress_state = SpaceCampaignProgressState.new()
	space_campaign_progress_state.campaign_progress_changed.connect(_on_space_campaign_progress_changed)
	space_campaign_progress_changed.emit(space_campaign_progress_state)

func _on_space_campaign_progress_changed(_revision: int) -> void:
	_save_space_campaign_progress_state()

func _save_space_campaign_progress_state() -> bool:
	return _save_campaign_progress_candidate(space_campaign_progress_state)

func _save_campaign_progress_candidate(candidate: SpaceCampaignProgressState) -> bool:
	if candidate == null or not candidate.get_validation_errors().is_empty():
		return false
	var payload := candidate.to_data()
	if payload.is_empty():
		return false
	var cfg := ConfigFile.new()
	cfg.set_value("campaign", "state", payload)
	var pending_path := SPACE_CAMPAIGN_SAVE_PATH + ".pending"
	if cfg.save(pending_path) != OK:
		return false
	var absolute_pending := ProjectSettings.globalize_path(pending_path)
	var absolute_target := ProjectSettings.globalize_path(SPACE_CAMPAIGN_SAVE_PATH)
	if FileAccess.file_exists(SPACE_CAMPAIGN_SAVE_PATH):
		var backup_path := SPACE_CAMPAIGN_SAVE_PATH + ".previous"
		var absolute_backup := ProjectSettings.globalize_path(backup_path)
		if FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(absolute_backup)
		if DirAccess.rename_absolute(absolute_target, absolute_backup) != OK:
			DirAccess.remove_absolute(absolute_pending)
			return false
		if DirAccess.rename_absolute(absolute_pending, absolute_target) != OK:
			DirAccess.rename_absolute(absolute_backup, absolute_target)
			DirAccess.remove_absolute(absolute_pending)
			return false
		DirAccess.remove_absolute(absolute_backup)
		return true
	if DirAccess.rename_absolute(absolute_pending, absolute_target) != OK:
		DirAccess.remove_absolute(absolute_pending)
		return false
	return true

func _save_space_progression_state() -> bool:
	return _save_progression_candidate(space_progression_state)

func _save_progression_candidate(candidate: SpacePlayerProgressionState) -> bool:
	if candidate == null or not candidate.get_validation_errors().is_empty():
		return false
	var payload := candidate.to_data()
	if payload.is_empty():
		return false
	var cfg := ConfigFile.new()
	cfg.set_value("progression", "state", payload)
	var pending_path := SPACE_PROGRESSION_SAVE_PATH + ".pending"
	if cfg.save(pending_path) != OK:
		return false
	var absolute_pending := ProjectSettings.globalize_path(pending_path)
	var absolute_target := ProjectSettings.globalize_path(SPACE_PROGRESSION_SAVE_PATH)
	var backup_path := SPACE_PROGRESSION_SAVE_PATH + ".previous"
	var absolute_backup := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(SPACE_PROGRESSION_SAVE_PATH):
		if FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(absolute_backup)
		if DirAccess.rename_absolute(absolute_target, absolute_backup) != OK:
			DirAccess.remove_absolute(absolute_pending)
			return false
		if DirAccess.rename_absolute(absolute_pending, absolute_target) != OK:
			DirAccess.rename_absolute(absolute_backup, absolute_target)
			DirAccess.remove_absolute(absolute_pending)
			return false
		DirAccess.remove_absolute(absolute_backup)
		return true
	if DirAccess.rename_absolute(absolute_pending, absolute_target) != OK:
		DirAccess.remove_absolute(absolute_pending)
		return false
	return true
