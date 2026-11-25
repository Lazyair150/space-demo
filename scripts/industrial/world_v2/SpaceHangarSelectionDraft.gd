extends RefCounted
class_name SpaceHangarSelectionDraft
## UI draft. Board Assignment is the source of truth for installable components;
## legacy fields are generated projections for the current Core runtime adapter.

var _inventory: Dictionary = {}
var _selection: Dictionary = {}
var _inventory_ready: bool = false
var _board: SpaceHangarBoardDefinition
var _assignments: Dictionary = {}

func configure(inventory: Dictionary, board: SpaceHangarBoardDefinition = null) -> bool:
	_inventory = inventory.duplicate(true)
	_inventory_ready = bool(_inventory.get("isReady", false))
	_board = board.duplicate(true) as SpaceHangarBoardDefinition if board != null else null
	_assignments.clear()
	_selection = {
		"shipId": "", "shipVersion": 0, "shipInstanceId": "",
		"deviceSelections": [], "parserId": "", "parserVersion": 0,
		"parserSlotId": "", "parserInstanceId": "", "workshopId": "",
		"workshopVersion": 0, "masterWorkshopInstanceId": "",
		"slaveWorkshopInstanceId": "", "skillSelections": [],
		"expectedBattleDurationLogicalMilli": 60000.0
	}
	if _inventory_ready:
		_apply_default_selection()
	return _inventory_ready


## Build a deterministic starter loadout from the player's actual owned inventory.
## This is a convenience default only; every assignment still passes the same
## exact-instance, compatibility, and Board validation as a manual selection.
func _apply_default_selection() -> void:
	var ships: Variant = _inventory.get("shipChoices", [])
	if ships is Array:
		for raw_ship in ships:
			if raw_ship is Dictionary and set_ship(
				String(raw_ship.get("id", "")),
				int(raw_ship.get("version", 0)),
				String(raw_ship.get("instanceId", ""))
			):
				break

	if _board == null:
		return

	var world_choices: Variant = _inventory.get("workshopWorldChoices", _inventory.get("workshopChoices", []))
	var workshop_instances: Variant = _inventory.get("workshopInstanceChoices", [])
	if world_choices is Array and workshop_instances is Array:
		for raw_world in world_choices:
			if not (raw_world is Dictionary):
				continue
			var world_id := String(raw_world.get("id", ""))
			var world_version := int(raw_world.get("version", 0))
			if world_id.is_empty() or world_version <= 0:
				continue
			var world_key := world_id + "@" + str(world_version)
			var compatible_ids: Array[String] = []
			for raw_instance in workshop_instances:
				if not (raw_instance is Dictionary):
					continue
				var compatible_worlds: Variant = raw_instance.get("compatibleWorldKeys", [])
				var instance_id := String(raw_instance.get("instanceId", ""))
				if not instance_id.is_empty() and compatible_worlds is Array and compatible_worlds.has(world_key):
					compatible_ids.append(instance_id)
				if compatible_ids.size() >= 2:
					break
			if compatible_ids.size() >= 2 and set_workshop(world_id, world_version, compatible_ids[0], compatible_ids[1]):
				break

	for slot in _board.slots:
		if slot == null:
			continue
		var slot_id := String(slot.slot_id)
		match slot.component_kind:
			"ore_parser":
				var parsers: Variant = _inventory.get("parserChoices", [])
				if parsers is Array:
					for parser in parsers:
						if parser is Dictionary and set_parser(String(parser.get("id", "")), int(parser.get("version", 0)), slot_id, String(parser.get("instanceId", ""))):
							break
			"skill":
				var skills: Variant = _inventory.get("skillChoices", [])
				if skills is Array:
					for skill in skills:
						if not (skill is Dictionary):
							continue
						if _contains_string(skill.get("allowedControlAreas", []), String(slot.control_area)) and set_skill(
							slot_id, String(skill.get("id", "")), int(skill.get("version", 0)),
							String(slot.control_area), String(skill.get("instanceId", ""))
						):
							break
			"production_device":
				var devices: Variant = _inventory.get("deviceChoices", [])
				if devices is Array:
					for device in devices:
						if device is Dictionary and set_device(slot_id, String(device.get("id", "")), int(device.get("version", 0)), String(device.get("instanceId", ""))):
							break

func set_ship(definition_id: String, version: int, instance_id: String = "") -> bool:
	var choice := _find_exact_choice("shipChoices", definition_id, version, instance_id)
	if choice.is_empty():
		return false
	_selection.shipInstanceId = String(choice.get("instanceId", ""))
	_selection.shipId = definition_id
	_selection.shipVersion = version
	return true

func set_parser(definition_id: String, version: int, slot_id: String, instance_id: String = "") -> bool:
	var choice := _find_exact_choice("parserChoices", definition_id, version, instance_id)
	if choice.is_empty() or not _assign(slot_id, "ore_parser", choice):
		return false
	_rebuild_legacy_projection()
	return true

func set_workshop(definition_id: String, version: int, master_instance_id: String = "", slave_instance_id: String = "") -> bool:
	var world_choices: Variant = _inventory.get("workshopWorldChoices", _inventory.get("workshopChoices", []))
	if _find_choice_in(world_choices, definition_id, version).is_empty():
		return false
	var world_key := definition_id + "@" + str(version)
	var master := _find_workshop_instance(master_instance_id, world_key) if not master_instance_id.is_empty() else {}
	var slave := _find_workshop_instance(slave_instance_id, world_key) if not slave_instance_id.is_empty() else {}
	# A World profile change must never silently uninstall an incompatible owned
	# workshop. Reject the change and preserve the existing Board assignments.
	if not master_instance_id.is_empty() and master.is_empty():
		return false
	if not slave_instance_id.is_empty() and slave.is_empty():
		return false
	if not master_instance_id.is_empty() and master_instance_id == slave_instance_id:
		return false
	var master_slot := _slot_for_role("master")
	var slave_slot := _slot_for_role("slave")
	if master_slot == null or slave_slot == null:
		return false
	var next := _assignments.duplicate(true)
	next.erase(String(master_slot.slot_id))
	next.erase(String(slave_slot.slot_id))
	if not master_instance_id.is_empty():
		var master_entry := SpaceHangarBoardAssignment.create_entry(master_slot, master)
		if master_entry.is_empty():
			return false
		next[String(master_slot.slot_id)] = master_entry
	if not slave_instance_id.is_empty():
		var slave_entry := SpaceHangarBoardAssignment.create_entry(slave_slot, slave)
		if slave_entry.is_empty():
			return false
		next[String(slave_slot.slot_id)] = slave_entry
	if not _validate_assignment_map(next, false, world_key).is_empty():
		return false
	_assignments = next
	_selection.workshopId = definition_id
	_selection.workshopVersion = version
	_rebuild_legacy_projection()
	return true

func set_device(slot_id: String, definition_id: String, version: int, instance_id: String = "") -> bool:
	var choice := _find_exact_choice("deviceChoices", definition_id, version, instance_id)
	if choice.is_empty() or not _assign(slot_id, "production_device", choice):
		return false
	_rebuild_legacy_projection()
	return true

func remove_device(slot_id: String) -> bool:
	if not _assignments.has(slot_id):
		return false
	if String(_assignments[slot_id].get("componentKind", "")) != "production_device":
		return false
	_assignments.erase(slot_id)
	_rebuild_legacy_projection()
	return true

func set_skill(order_definition_key: String, skill_id: String, version: int, control_area: String, instance_id: String = "") -> bool:
	var choice := _find_exact_choice("skillChoices", skill_id, version, instance_id)
	if choice.is_empty() or not _contains_string(choice.get("allowedControlAreas", []), control_area):
		return false
	var slot := _slot_by_id(order_definition_key)
	if slot == null or slot.component_kind != "skill" or slot.control_area != control_area:
		return false
	if not _assign(order_definition_key, "skill", choice):
		return false
	_rebuild_legacy_projection()
	return true

func remove_skill(order_definition_key: String) -> bool:
	if not _assignments.has(order_definition_key):
		return false
	if String(_assignments[order_definition_key].get("componentKind", "")) != "skill":
		return false
	_assignments.erase(order_definition_key)
	_rebuild_legacy_projection()
	return true

func assign_instance(slot_id: String, owned_instance_id: String) -> bool:
	var slot := _slot_by_id(slot_id)
	if slot == null or owned_instance_id.strip_edges().is_empty():
		return false
	var choice := SpaceHangarBoardAssignment._find_inventory_instance(_inventory, owned_instance_id)
	if choice.is_empty() or not _assign(slot_id, slot.component_kind, choice):
		return false
	_rebuild_legacy_projection()
	return true

func unassign_slot(slot_id: String) -> bool:
	if not _assignments.has(slot_id):
		return false
	_assignments.erase(slot_id)
	_rebuild_legacy_projection()
	return true

func get_assignment(slot_id: String) -> Dictionary:
	return _assignments.get(slot_id, {}).duplicate(true)

func validate_assignments() -> PackedStringArray:
	return _validate_assignment_map(_assignments, true)

func build_assignment_snapshot() -> Dictionary:
	if _board == null or not validate_assignments().is_empty():
		return {}
	return SpaceHangarBoardAssignment.build_snapshot(_board, _assignments)

func set_expected_battle_duration(logical_milli: float) -> bool:
	if not is_finite(logical_milli) or logical_milli <= 0.0:
		return false
	_selection.expectedBattleDurationLogicalMilli = logical_milli
	return true

func build_selection() -> SpaceHangarSelection:
	if not _inventory_ready or (_board != null and not validate_assignments().is_empty()):
		return null
	var data := snapshot_data()
	var selection := SpaceHangarSelection.from_data(data)
	if not selection.validate().is_empty():
		return null
	return selection

func snapshot_data() -> Dictionary:
	var result := _selection.duplicate(true)
	result["boardAssignments"] = build_assignment_snapshot()
	return result

func is_ready() -> bool:
	return _inventory_ready

func _assign(slot_id: String, expected_kind: String, choice: Dictionary) -> bool:
	var slot := _slot_by_id(slot_id)
	if slot == null or slot.component_kind != expected_kind:
		return false
	var entry := SpaceHangarBoardAssignment.create_entry(slot, choice)
	if entry.is_empty():
		return false
	var next := _assignments.duplicate(true)
	next[slot_id] = entry
	if not _validate_assignment_map(next).is_empty():
		return false
	_assignments = next
	return true

func _validate_assignment_map(assignments: Dictionary, require_complete: bool = false, world_key_override: String = "") -> PackedStringArray:
	if _board == null:
		return PackedStringArray()
	var errors := SpaceHangarBoardAssignment.validate(_board, assignments, _inventory, require_complete)
	if not errors.is_empty():
		return errors
	var world_key := world_key_override
	if world_key.is_empty() and not String(_selection.get("workshopId", "")).is_empty():
		world_key = String(_selection.workshopId) + "@" + str(int(_selection.workshopVersion))
	if not world_key.is_empty():
		for slot_id in assignments:
			var entry: Dictionary = assignments[slot_id]
			if String(entry.get("componentKind", "")) == "workshop":
				if _find_workshop_instance(String(entry.get("ownedInstanceId", "")), world_key).is_empty():
					errors.append("workshop instance is incompatible with selected World rules profile: " + String(slot_id))
	return errors

func _slot_by_id(slot_id: String) -> SpaceHangarBoardSlotDefinition:
	return _board.resolve_slot(slot_id) if _board != null else null

func _slot_for_role(role: String) -> SpaceHangarBoardSlotDefinition:
	if _board == null:
		return null
	for slot in _board.slots:
		if slot != null and slot.area_id == "workshop" and slot.role_id == role:
			return _board.resolve_slot(String(slot.slot_id))
	return null

func _rebuild_legacy_projection() -> void:
	_selection.deviceSelections = []
	_selection.skillSelections = []
	_selection.parserId = ""
	_selection.parserVersion = 0
	_selection.parserSlotId = ""
	_selection.parserInstanceId = ""
	_selection.masterWorkshopInstanceId = ""
	_selection.slaveWorkshopInstanceId = ""
	for slot_id in _assignments:
		var entry: Dictionary = _assignments[slot_id]
		var kind := String(entry.get("componentKind", ""))
		match kind:
			"ore_parser":
				_selection.parserId = String(entry.definitionId)
				_selection.parserVersion = int(entry.definitionVersion)
				_selection.parserSlotId = slot_id
				_selection.parserInstanceId = String(entry.ownedInstanceId)
			"workshop":
				var slot := _slot_by_id(slot_id)
				if slot != null and slot.role_id == "master":
					_selection.masterWorkshopInstanceId = String(entry.ownedInstanceId)
				elif slot != null and slot.role_id == "slave":
					_selection.slaveWorkshopInstanceId = String(entry.ownedInstanceId)
			"production_device":
				_selection.deviceSelections.append({
					"slotId": slot_id, "definitionId": String(entry.definitionId),
					"definitionVersion": int(entry.definitionVersion), "instanceId": String(entry.ownedInstanceId)
				})
			"skill":
				var slot := _slot_by_id(slot_id)
				_selection.skillSelections.append({
					"orderDefinitionKey": slot_id, "skillId": String(entry.definitionId),
					"definitionVersion": int(entry.definitionVersion),
					"controlArea": slot.control_area if slot != null else "none",
					"instanceId": String(entry.ownedInstanceId)
				})
	_selection.deviceSelections.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("slotId", "")) < String(b.get("slotId", "")))
	_selection.skillSelections.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("orderDefinitionKey", "")) < String(b.get("orderDefinitionKey", "")))

func _find_choice_in(raw_choices: Variant, definition_id: String, version: int) -> Dictionary:
	if not (raw_choices is Array):
		return {}
	for choice in raw_choices:
		if choice is Dictionary and String(choice.get("id", "")) == definition_id and int(choice.get("version", 0)) == version:
			return choice
	return {}

func _find_workshop_instance(instance_id: String, world_key: String = "") -> Dictionary:
	if instance_id.is_empty():
		return {}
	var choices: Variant = _inventory.get("workshopInstanceChoices", [])
	if not (choices is Array):
		return {}
	for choice in choices:
		if choice is Dictionary and String(choice.get("instanceId", "")) == instance_id:
			var compatible_worlds: Array = choice.get("compatibleWorldKeys", [])
			if world_key.is_empty() or compatible_worlds.has(world_key):
				var result: Dictionary = choice.duplicate(true)
				result["itemKind"] = "workshop"
				return result
	return {}

func _find_exact_choice(collection_key: String, definition_id: String, version: int, instance_id: String = "") -> Dictionary:
	if not _inventory_ready or definition_id.strip_edges().is_empty() or version <= 0:
		return {}
	var choices: Variant = _inventory.get(collection_key, [])
	if not (choices is Array):
		return {}
	for raw_choice in choices:
		if not (raw_choice is Dictionary):
			continue
		if String(raw_choice.get("id", "")) == definition_id and int(raw_choice.get("version", 0)) == version:
			var choice_instance_id := String(raw_choice.get("instanceId", ""))
			if (not instance_id.is_empty() and choice_instance_id != instance_id) or (instance_id.is_empty() and not choice_instance_id.is_empty()):
				continue
			var result: Dictionary = raw_choice.duplicate(true)
			result["itemKind"] = _kind_for_collection(collection_key)
			return result
	return {}

func _kind_for_collection(collection_key: String) -> String:
	match collection_key:
		"parserChoices": return "ore_parser"
		"deviceChoices": return "production_device"
		"skillChoices": return "skill"
	return ""

func _contains_string(values: Variant, expected: String) -> bool:
	if values is Array:
		for value in values:
			if String(value) == expected:
				return true
	elif values is PackedStringArray:
		return values.has(expected)
	return false
