extends Resource
class_name SpaceHangarBoardSlotDefinition
## One physical position on the player's configurable assembly board.

@export var slot_id: StringName = &""
@export_enum("workshop", "decomposition", "orders", "production") var area_id: String = "orders"
@export_enum("workshop", "ore_parser", "skill", "production_device") var component_kind: String = "skill"
@export var display_name: String = ""
## Only workshop positions use role_id (master/slave). The role belongs to the slot, not the component.
@export_enum("none", "master", "slave") var role_id: String = "none"
## Only skill slots use control_area; passive scheduling remains Core-owned.
@export_enum("none", "Active", "Passive") var control_area: String = "none"
@export var required: bool = true

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if slot_id == &"" or display_name.strip_edges().is_empty():
		errors.append("board slot requires a stable ID and display name")
	var valid_pair := (
		(area_id == "workshop" and component_kind == "workshop" and role_id in ["master", "slave"] and control_area == "none")
		or (area_id == "decomposition" and component_kind == "ore_parser" and role_id == "none" and control_area == "none")
		or (area_id == "orders" and component_kind == "skill" and role_id == "none" and control_area in ["Active", "Passive"])
		or (area_id == "production" and component_kind == "production_device" and role_id == "none" and control_area == "none")
	)
	if not valid_pair:
		errors.append("board slot area/component/role/control-area combination is invalid")
	return errors
