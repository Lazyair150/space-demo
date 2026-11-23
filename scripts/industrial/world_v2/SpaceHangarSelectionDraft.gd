extends RefCounted
class_name SpaceHangarSelectionDraft
## Mutable UI-side draft. It stores exact authored identities and never resolves runtime definitions.
## SpaceHangarLoadoutAssembler remains the final authority when freezing a battle loadout.

var _inventory: Dictionary = {}
var _selection: Dictionary = {}
var _inventory_ready: bool = false

func configure(inventory: Dictionary) -> bool:
	_inventory = inventory.duplicate(true)
	_inventory_ready = bool(_inventory.get("isReady", false))
	_selection = {
		"shipId": "",
		"shipVersion": 0,
		"shipInstanceId": "",
		"deviceSelections": [],
		"parserId": "",
		"parserVersion": 0,
		"parserSlotId": "",
		"parserInstanceId": "",
		"workshopId": "",
		"workshopVersion": 0,
		"masterWorkshopInstanceId": "",
		"slaveWorkshopInstanceId": "",
		"skillSelections": [],
		"expectedBattleDurationLogicalMilli": 0.0
	}
	return _inventory_ready

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
	if slot_id.strip_edges().is_empty() or choice.is_empty():
		return false
	_selection.parserInstanceId = String(choice.get("instanceId", ""))
	for raw_device in _selection.deviceSelections:
		if String(raw_device.get("slotId", "")) == slot_id:
			return false
	_selection.parserId = definition_id
	_selection.parserVersion = version
	_selection.parserSlotId = slot_id
	return true

func set_workshop(definition_id: String, version: int, master_instance_id: String = "", slave_instance_id: String = "") -> bool:
	var world_choices: Variant = _inventory.get("workshopWorldChoices", _inventory.get("workshopChoices", []))
	var world_choice := _find_choice_in(world_choices, definition_id, version)
	if world_choice.is_empty():
		return false
	if not master_instance_id.is_empty() and _find_workshop_instance(master_instance_id).is_empty():
		return false
	if not slave_instance_id.is_empty() and _find_workshop_instance(slave_instance_id).is_empty():
		return false
	if not master_instance_id.is_empty() and master_instance_id == slave_instance_id:
		return false
	_selection.workshopId = definition_id
	_selection.workshopVersion = version
	_selection.masterWorkshopInstanceId = master_instance_id
	_selection.slaveWorkshopInstanceId = slave_instance_id
	return true

func _find_choice_in(raw_choices: Variant, definition_id: String, version: int) -> Dictionary:
	if not (raw_choices is Array):
		return {}
	for choice in raw_choices:
		if choice is Dictionary and String(choice.get("id", "")) == definition_id and int(choice.get("version", 0)) == version:
			return choice
	return {}

func _find_workshop_instance(instance_id: String) -> Dictionary:
	if instance_id.is_empty():
		return {}
	var choices: Variant = _inventory.get("workshopInstanceChoices", [])
	if not (choices is Array):
		return {}
	for choice in choices:
		if choice is Dictionary and String(choice.get("instanceId", "")) == instance_id:
			return choice
	return {}

func set_device(slot_id: String, definition_id: String, version: int, instance_id: String = "") -> bool:
	if slot_id.strip_edges().is_empty() or slot_id == String(_selection.get("parserSlotId", "")):
		return false
	var choice := _find_exact_choice("deviceChoices", definition_id, version, instance_id)
	if choice.is_empty():
		return false
	var devices: Array = _selection.deviceSelections
	for index in range(devices.size()):
		if String(devices[index].get("slotId", "")) == slot_id:
			devices[index] = _device_choice(slot_id, definition_id, version, String(choice.get("instanceId", "")))
			_selection.deviceSelections = devices
			return true
	devices.append(_device_choice(slot_id, definition_id, version, String(choice.get("instanceId", ""))))
	_selection.deviceSelections = devices
	return true

func remove_device(slot_id: String) -> bool:
	var devices: Array = _selection.deviceSelections
	for index in range(devices.size() - 1, -1, -1):
		if String(devices[index].get("slotId", "")) == slot_id:
			devices.remove_at(index)
			_selection.deviceSelections = devices
			return true
	return false

func set_skill(order_definition_key: String, skill_id: String, version: int, control_area: String, instance_id: String = "") -> bool:
	if order_definition_key.strip_edges().is_empty() or control_area.strip_edges().is_empty():
		return false
	var choice := _find_exact_choice("skillChoices", skill_id, version, instance_id)
	if choice.is_empty() or not _contains_string(choice.get("allowedControlAreas", []), control_area):
		return false
	var skills: Array = _selection.skillSelections
	var replacement := {
		"orderDefinitionKey": order_definition_key,
		"skillId": skill_id,
		"definitionVersion": version,
		"controlArea": control_area,
		"instanceId": String(choice.get("instanceId", ""))
	}
	for index in range(skills.size()):
		if String(skills[index].get("orderDefinitionKey", "")) == order_definition_key:
			skills[index] = replacement
			_selection.skillSelections = skills
			return true
	skills.append(replacement)
	_selection.skillSelections = skills
	return true

func remove_skill(order_definition_key: String) -> bool:
	var skills: Array = _selection.skillSelections
	for index in range(skills.size() - 1, -1, -1):
		if String(skills[index].get("orderDefinitionKey", "")) == order_definition_key:
			skills.remove_at(index)
			_selection.skillSelections = skills
			return true
	return false

func set_expected_battle_duration(logical_milli: float) -> bool:
	if not is_finite(logical_milli) or logical_milli <= 0.0:
		return false
	_selection.expectedBattleDurationLogicalMilli = logical_milli
	return true

func build_selection() -> SpaceHangarSelection:
	if not _inventory_ready:
		return null
	var selection := SpaceHangarSelection.from_data(_selection)
	if not selection.validate().is_empty():
		return null
	return selection

func snapshot_data() -> Dictionary:
	return _selection.duplicate(true)

func is_ready() -> bool:
	return _inventory_ready

func _has_exact_choice(collection_key: String, definition_id: String, version: int) -> bool:
	return not _find_exact_choice(collection_key, definition_id, version).is_empty()

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
			return raw_choice
	return {}

func _contains_string(values: Variant, expected: String) -> bool:
	if values is Array:
		for value in values:
			if String(value) == expected:
				return true
	elif values is PackedStringArray:
		return values.has(expected)
	return false

func _device_choice(slot_id: String, definition_id: String, version: int, instance_id: String = "") -> Dictionary:
	return {
		"slotId": slot_id,
		"definitionId": definition_id,
		"definitionVersion": version,
		"instanceId": instance_id
	}

