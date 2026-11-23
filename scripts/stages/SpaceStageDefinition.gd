extends Resource
class_name SpaceStageDefinition
## Authored finite mission/stage. Combat presentation never enters Jar order contracts.

const OBJECTIVES := ["eliminate_all", "survive_duration", "protect_target", "collect_resource", "boss"]
const SEGMENTS := ["warmup", "pressure", "elite", "rest", "boss"]

@export var stage_id: StringName = &""
@export var definition_version: int = 1
@export var campaign_id: StringName = &""
@export_range(1, 999, 1) var sequence_index: int = 1
@export var display_name: String = ""
@export_multiline var briefing: String = ""
@export_enum("eliminate_all", "survive_duration", "protect_target", "collect_resource", "boss") var objective: String = "eliminate_all"
@export_range(1, 100, 1) var recommended_loadout_level: int = 1
@export_range(1, 30, 1) var estimated_minutes: int = 5
## Each entry is an authored encounter beat, not an unbounded wave formula.
## Required: segment, chaser_count, shooter_count, elite_count, break_seconds.
@export var wave_plans: Array[Dictionary] = []
## Explicit progression reward payload; actual reward settlement is owned by campaign progression.
@export var completion_rewards: Dictionary = {}
## Optional stage-specific tuning. These are authored values, never inferred by a global multiplier.
@export var difficulty_profile: Dictionary = {}

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if stage_id == &"" or definition_version <= 0 or campaign_id == &"" or sequence_index <= 0:
		errors.append("stage requires stable versioned identity and campaign position")
	if display_name.strip_edges().is_empty() or not OBJECTIVES.has(objective):
		errors.append("stage requires a display name and supported objective")
	if recommended_loadout_level <= 0 or estimated_minutes <= 0:
		errors.append("stage recommendation and estimated duration must be positive")
	if wave_plans.is_empty():
		errors.append("finite stage requires at least one authored encounter beat")
	for index in range(wave_plans.size()):
		var beat: Dictionary = wave_plans[index]
		if not SEGMENTS.has(String(beat.get("segment", ""))):
			errors.append("wave plan %d has an unsupported segment" % (index + 1))
		var total := 0
		for key in ["chaser_count", "shooter_count", "elite_count"]:
			var value: Variant = beat.get(key, null)
			if typeof(value) != TYPE_INT or int(value) < 0:
				errors.append("wave plan %d requires non-negative integer %s" % [index + 1, key])
			else:
				total += int(value)
		if total <= 0 and objective != "survive_duration":
			errors.append("wave plan %d must spawn enemies for this objective" % (index + 1))
		var break_value: Variant = beat.get("break_seconds", null)
		if (typeof(break_value) not in [TYPE_INT, TYPE_FLOAT]) or not is_finite(float(break_value)) or float(break_value) < 0.0:
			errors.append("wave plan %d requires a finite non-negative break_seconds" % (index + 1))
		if beat.has("duration_seconds"):
			var duration: Variant = beat.duration_seconds
			if (typeof(duration) not in [TYPE_INT, TYPE_FLOAT]) or not is_finite(float(duration)) or float(duration) <= 0.0:
				errors.append("wave plan %d duration_seconds must be positive" % (index + 1))
	for key in completion_rewards:
		if str(key).strip_edges().is_empty():
			errors.append("completion reward keys cannot be empty")
	return errors

func is_valid() -> bool:
	return get_validation_errors().is_empty()

func wave_count() -> int:
	return wave_plans.size()

func wave_plan(one_based_index: int) -> Dictionary:
	if not is_valid() or one_based_index < 1 or one_based_index > wave_plans.size():
		return {}
	return wave_plans[one_based_index - 1].duplicate(true)
