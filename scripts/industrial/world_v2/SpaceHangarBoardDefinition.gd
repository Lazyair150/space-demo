extends Resource
class_name SpaceHangarBoardDefinition
## Player-facing circuit-board layout. Slots define positions; owned instances provide components.

@export var board_id: StringName = &""
@export var definition_version: int = 1
@export var display_name: String = ""
@export var slots: Array[SpaceHangarBoardSlotDefinition] = []

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if board_id == &"" or definition_version <= 0 or display_name.strip_edges().is_empty():
		errors.append("Hangar board requires a stable versioned identity and display name")
	var ids := {}
	var master_count := 0
	var slave_count := 0
	var parser_count := 0
	for slot in slots:
		if slot == null:
			errors.append("Hangar board cannot contain null slots")
			continue
		errors.append_array(slot.get_validation_errors())
		var key := String(slot.slot_id)
		if ids.has(key):
			errors.append("Hangar board slot IDs must be unique: " + key)
		ids[key] = true
		if slot.area_id == "workshop" and slot.role_id == "master":
			master_count += 1
		if slot.area_id == "workshop" and slot.role_id == "slave":
			slave_count += 1
		if slot.component_kind == "ore_parser":
			parser_count += 1
	if master_count != 1 or slave_count != 1:
		errors.append("current World V2 board requires exactly one Master and one Slave workshop position")
	if parser_count != 1:
		errors.append("current parser runtime requires exactly one universal decomposition position")
	return errors

func build_hangar_configuration() -> Dictionary:
	if not get_validation_errors().is_empty():
		return {}
	var parser_slot := ""
	var master_slot := ""
	var slave_slot := ""
	var devices: PackedStringArray = PackedStringArray()
	var order_bindings: Array[Dictionary] = []
	for slot in slots:
		match slot.component_kind:
			"ore_parser":
				parser_slot = String(slot.slot_id)
			"workshop":
				if slot.role_id == "master":
					master_slot = String(slot.slot_id)
				elif slot.role_id == "slave":
					slave_slot = String(slot.slot_id)
			"production_device":
				devices.append(String(slot.slot_id))
			"skill":
				order_bindings.append({
					"orderDefinitionKey": String(slot.slot_id),
					"label": slot.display_name,
					"controlArea": slot.control_area,
					"required": slot.required
				})
	return {
		"parserSlotId": parser_slot,
		"masterWorkshopSlotId": master_slot,
		"slaveWorkshopSlotId": slave_slot,
		"deviceSlotIds": devices,
		"skillOrderBindings": order_bindings
	}

func resolve_slot(slot_id: String) -> SpaceHangarBoardSlotDefinition:
	for slot in slots:
		if slot != null and String(slot.slot_id) == slot_id:
			return slot.duplicate(true) as SpaceHangarBoardSlotDefinition
	return null
