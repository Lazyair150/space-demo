extends Resource
class_name SpaceShipDefinition
## Versioned, author-authored ship production profile. No gameplay values are supplied here.

@export var ship_id: StringName = &""
@export var definition_version: int = 1
@export var display_name: String = ""
@export var expected_stone_progress_per_second_by_shape: Dictionary = {}

func get_validation_errors(configured_shapes: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	if ship_id == &"" or definition_version <= 0:
		errors.append("ship definition identity/version is invalid")
	if display_name.strip_edges().is_empty():
		errors.append("ship display name is required")
	if configured_shapes.is_empty() or expected_stone_progress_per_second_by_shape.size() != configured_shapes.size():
		errors.append("ship stone profile must cover the exact configured Jar shape vocabulary")
	for shape in configured_shapes:
		var key := String(shape)
		if not expected_stone_progress_per_second_by_shape.has(key):
			errors.append("ship stone profile is missing shape: " + key)
			continue
		var raw_rate: Variant = expected_stone_progress_per_second_by_shape[key]
		if (typeof(raw_rate) != TYPE_INT and typeof(raw_rate) != TYPE_FLOAT) or not is_finite(float(raw_rate)) or float(raw_rate) < 0.0 or float(raw_rate) > 1000000000.0:
			errors.append("ship stone rate is outside the supported fixed-point range: " + key)
	for key in expected_stone_progress_per_second_by_shape:
		if not configured_shapes.has(String(key)):
			errors.append("ship stone profile contains an unconfigured shape: " + String(key))
	return errors

func build_selection(configured_shapes: Array) -> Dictionary:
	if not get_validation_errors(configured_shapes).is_empty():
		return {}
	return {
		"definitionId": String(ship_id),
		"definitionVersion": definition_version,
		"shipResourceProfile": {
			"expectedStoneProgressPerSecondByShape": expected_stone_progress_per_second_by_shape.duplicate(true)
		}
	}
