extends Resource
class_name SpaceProgressionCurveDefinition
## Versioned, data-authored progression curve.
## The evaluator is generic; attribute keys and their gameplay meaning belong to
## the item subsystem (ship, parser, workshop, skill, or production device).

const ITEM_KINDS := ["ship", "ore_parser", "production_device", "workshop", "skill"]
const INTERPOLATIONS := ["linear", "step"]

@export var curve_id: StringName = &""
@export var definition_version: int = 1
@export_enum("ship", "ore_parser", "production_device", "workshop", "skill") var item_kind: String = "ship"
@export_range(1, 1000, 1) var max_level: int = 10
## Cumulative total XP required to ENTER each level. Level 1 is implicit at 0 XP.
## Example: {"2": 100, "3": 260, "4": 480}
@export var experience_threshold_by_level: Dictionary = {}
## Attribute key -> [{ "level": 1, "value": 0.0 }, ...].
## Values are raw subsystem-owned growth values, not universal multipliers.
@export var attribute_keyframes: Dictionary = {}
@export_enum("linear", "step") var interpolation: String = "linear"

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if curve_id == &"" or definition_version <= 0:
		errors.append("progression curve requires an exact curve identity/version")
	if not ITEM_KINDS.has(item_kind):
		errors.append("progression curve item_kind is unsupported")
	if max_level < 1:
		errors.append("progression curve max_level must be positive")
	if not INTERPOLATIONS.has(interpolation):
		errors.append("progression curve interpolation is unsupported")

	if experience_threshold_by_level.size() != maxi(0, max_level - 1):
		errors.append("experience thresholds must define every level from 2 through max_level exactly once")
	var previous_threshold := 0
	for level in range(2, max_level + 1):
		var key := str(level)
		if not experience_threshold_by_level.has(key):
			errors.append("missing cumulative experience threshold for level " + key)
			continue
		var raw_threshold: Variant = experience_threshold_by_level[key]
		if typeof(raw_threshold) != TYPE_INT or int(raw_threshold) <= previous_threshold:
			errors.append("experience thresholds must be positive, integer, and strictly increasing")
			continue
		previous_threshold = int(raw_threshold)
	for raw_key in experience_threshold_by_level:
		var parsed_level := int(str(raw_key))
		if str(parsed_level) != str(raw_key) or parsed_level < 2 or parsed_level > max_level:
			errors.append("experience threshold contains an invalid level key: " + str(raw_key))

	if attribute_keyframes.is_empty():
		errors.append("progression curve must define at least one subsystem attribute")
	for raw_attribute in attribute_keyframes:
		var attribute := str(raw_attribute).strip_edges()
		var points: Variant = attribute_keyframes[raw_attribute]
		if attribute.is_empty() or not (points is Array) or points.is_empty():
			errors.append("attribute keyframes require a non-empty key and point array")
			continue
		var previous_level := 0
		for point in points:
			if not (point is Dictionary):
				errors.append("attribute keyframe must be a dictionary: " + attribute)
				continue
			var point_level := int(point.get("level", 0))
			var raw_value: Variant = point.get("value", null)
			if point_level <= previous_level or point_level < 1 or point_level > max_level:
				errors.append("attribute keyframe levels must be strictly increasing within the curve range: " + attribute)
			previous_level = point_level
			if typeof(raw_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw_value)):
				errors.append("attribute keyframe values must be finite numbers: " + attribute)
		if points[0] is Dictionary and int(points[0].get("level", 0)) != 1:
			errors.append("each attribute curve must begin at level 1: " + attribute)
	return errors

func is_valid() -> bool:
	return get_validation_errors().is_empty()

func level_for_experience(total_experience: int) -> int:
	if not is_valid() or total_experience < 0:
		return 0
	var result := 1
	for level in range(2, max_level + 1):
		if total_experience < int(experience_threshold_by_level[str(level)]):
			break
		result = level
	return result

func build_growth_attributes(level: int) -> Dictionary:
	if not is_valid() or level < 1 or level > max_level:
		return {}
	var result := {}
	for raw_attribute in attribute_keyframes:
		result[str(raw_attribute)] = _sample_attribute(attribute_keyframes[raw_attribute], level)
	return result

func experience_required_for_level(level: int) -> int:
	if not is_valid() or level < 1 or level > max_level:
		return -1
	return 0 if level == 1 else int(experience_threshold_by_level[str(level)])

func _sample_attribute(points: Array, target_level: int) -> float:
	var previous: Dictionary = points[0]
	if target_level <= int(previous.level):
		return float(previous.value)
	for index in range(1, points.size()):
		var next_point: Dictionary = points[index]
		var next_level := int(next_point.level)
		if target_level <= next_level:
			if interpolation == "step":
				return float(previous.value)
			var span := float(next_level - int(previous.level))
			var weight := float(target_level - int(previous.level)) / span
			return lerpf(float(previous.value), float(next_point.value), weight)
		previous = next_point
	return float(previous.value)
