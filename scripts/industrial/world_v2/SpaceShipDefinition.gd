extends Resource
class_name SpaceShipDefinition
## Versioned, author-authored ship production profile. No gameplay values are supplied here.

@export var ship_id: StringName = &""
@export var definition_version: int = 1
@export var display_name: String = ""
@export var display_icon: Texture2D
@export var display_hull_texture: Texture2D
@export var display_anchors: Array[SpaceShipDisplayAnchor] = []
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

func get_display_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var anchor_ids := {}
	var logical_slots := {}
	for anchor in display_anchors:
		if anchor == null:
			errors.append("ship display anchor cannot be null")
			continue
		for anchor_error in anchor.get_validation_errors():
			errors.append("ship display anchor: " + anchor_error)
		var anchor_key := String(anchor.anchor_id)
		var slot_key := anchor.component_kind + ":" + anchor.logical_slot_id
		if anchor_ids.has(anchor_key):
			errors.append("ship display anchor IDs must be unique: " + anchor_key)
		anchor_ids[anchor_key] = true
		if logical_slots.has(slot_key):
			errors.append("ship display anchors must map each component slot once: " + slot_key)
		logical_slots[slot_key] = true
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
