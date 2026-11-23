extends Resource
class_name SpaceShipDisplayAnchor
## Authored presentation anchor. logical_slot_id is an opaque gameplay slot identity;
## normalized_position is only a 2D preview coordinate and never affects gameplay.

@export var anchor_id: StringName = &""
@export var logical_slot_id: String = ""
@export_enum("device", "parser") var component_kind: String = "device"
@export var normalized_position: Vector2 = Vector2(0.5, 0.5)
@export_range(-360.0, 360.0, 0.1) var rotation_degrees: float = 0.0
@export_range(0.1, 4.0, 0.05) var icon_scale: float = 1.0

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if anchor_id == &"":
		errors.append("display anchor identity is required")
	if logical_slot_id.strip_edges().is_empty():
		errors.append("display anchor logical slot ID is required")
	if not ["device", "parser"].has(component_kind):
		errors.append("display anchor component kind must be device or parser")
	if not is_finite(normalized_position.x) or not is_finite(normalized_position.y):
		errors.append("display anchor position must be finite")
	elif normalized_position.x < 0.0 or normalized_position.x > 1.0 or normalized_position.y < 0.0 or normalized_position.y > 1.0:
		errors.append("display anchor position must be normalized to [0, 1]")
	if not is_finite(rotation_degrees) or rotation_degrees < -360.0 or rotation_degrees > 360.0 or not is_finite(icon_scale) or icon_scale < 0.1 or icon_scale > 4.0:
		errors.append("display anchor transform is outside its authored range")
	return errors

func duplicate_anchor() -> SpaceShipDisplayAnchor:
	var copy := SpaceShipDisplayAnchor.new()
	copy.anchor_id = anchor_id
	copy.logical_slot_id = logical_slot_id
	copy.component_kind = component_kind
	copy.normalized_position = normalized_position
	copy.rotation_degrees = rotation_degrees
	copy.icon_scale = icon_scale
	return copy
