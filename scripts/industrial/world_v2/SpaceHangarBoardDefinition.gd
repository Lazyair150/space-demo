extends Resource
class_name SpaceHangarBoardDefinition
## Configurable circuit-board layout. Slots own positions; player-owned instances are assigned separately.
## Core's current runtime adapter still has a narrower projection contract, exposed explicitly below.

@export var board_id: StringName = &""
@export var definition_version: int = 1
@export var display_name: String = ""
@export var slots: Array[SpaceHangarBoardSlotDefinition] = []

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if board_id == &"" or definition_version <= 0 or display_name.strip_edges().is_empty():
		errors.append("Hangar board requires a stable versioned identity and display name")
	if slots.is_empty():
		errors.append("Hangar board must define at least one component position")
	var ids := {}
	for slot in slots:
		if slot == null:
			errors.append("Hangar board cannot contain null slots")
			continue
		errors.append_array(slot.get_validation_errors())
		var key := String(slot.slot_id)
		if ids.has(key):
			errors.append("Hangar board slot IDs must be unique: " + key)
		ids[key] = true
	return errors

## Runtime projection is deliberately separate from board validity. A board may describe
## more positions than the current World V2 adapters can execute; it must never silently
## collapse multiple positions into one legacy field.
func get_runtime_projection_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var master_count := 0
	var slave_count := 0
	var parser_count := 0
	for slot in slots:
		if slot == null:
			continue
		if slot.area_id == "workshop" and slot.role_id == "master":
			master_count += 1
		elif slot.area_id == "workshop" and slot.role_id == "slave":
			slave_count += 1
		if slot.component_kind == "ore_parser":
			parser_count += 1
	if master_count != 1 or slave_count != 1:
		errors.append("current World V2 adapter requires exactly one Master and one Slave workshop position")
	if parser_count != 1:
		errors.append("current parser runtime supports exactly one decomposition position; multi-parser execution is not implemented")
	return errors

func build_hangar_configuration() -> Dictionary:
	if not get_validation_errors().is_empty() or not get_runtime_projection_errors().is_empty():
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

func get_slots_for_area(area_id: String) -> Array[SpaceHangarBoardSlotDefinition]:
	var result: Array[SpaceHangarBoardSlotDefinition] = []
	for slot in slots:
		if slot != null and slot.area_id == area_id:
			result.append(slot.duplicate(true) as SpaceHangarBoardSlotDefinition)
	return result

func build_slot_index() -> Dictionary:
	if not get_validation_errors().is_empty():
		return {}
	var result := {}
	for slot in slots:
		result[String(slot.slot_id)] = {
			"slotId": String(slot.slot_id),
			"areaId": slot.area_id,
			"subAreaId": slot.sub_area_id,
			"componentKind": slot.component_kind,
			"displayName": slot.display_name,
			"roleId": slot.role_id,
			"controlArea": slot.control_area,
			"required": slot.required
		}
	return result

func resolve_slot(slot_id: String) -> SpaceHangarBoardSlotDefinition:
	for slot in slots:
		if slot != null and String(slot.slot_id) == slot_id:
			return slot.duplicate(true) as SpaceHangarBoardSlotDefinition
	return null

func build_frozen_snapshot() -> Dictionary:
	if not get_validation_errors().is_empty():
		return {}
	var frozen_slots: Array[Dictionary] = []
	for slot in slots:
		frozen_slots.append({
			"slotId": String(slot.slot_id),
			"areaId": slot.area_id,
			"subAreaId": slot.sub_area_id,
			"componentKind": slot.component_kind,
			"displayName": slot.display_name,
			"roleId": slot.role_id,
			"controlArea": slot.control_area,
			"required": slot.required
		})
	return {
		"schemaVersion": 2,
		"boardId": String(board_id),
		"definitionVersion": definition_version,
		"displayName": display_name,
		"slots": frozen_slots
	}
