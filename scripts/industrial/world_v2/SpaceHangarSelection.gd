extends RefCounted
class_name SpaceHangarSelection
## Explicit player choices only. This object carries identities, never resolved runtime data.

var ship_id: String = ""
var ship_version: int = 0
var ship_instance_id: String = ""
var device_selections: Array = []
var parser_id: String = ""
var parser_version: int = 0
var parser_slot_id: String = ""
var parser_instance_id: String = ""
var workshop_id: String = ""
var workshop_version: int = 0
var master_workshop_instance_id: String = ""
var slave_workshop_instance_id: String = ""
var skill_selections: Array = []
var expected_battle_duration_logical_milli: float = 0.0
var _source_errors: PackedStringArray = PackedStringArray()

static func from_data(data: Dictionary) -> SpaceHangarSelection:
	var selection := SpaceHangarSelection.new()
	selection.ship_id = String(data.get("shipId", ""))
	selection.ship_version = int(data.get("shipVersion", 0))
	selection.ship_instance_id = String(data.get("shipInstanceId", ""))
	var raw_devices: Variant = data.get("deviceSelections", [])
	if raw_devices is Array:
		selection.device_selections = raw_devices.duplicate(true)
	else:
		selection._source_errors.append("deviceSelections must be an array")
	selection.parser_id = String(data.get("parserId", ""))
	selection.parser_version = int(data.get("parserVersion", 0))
	selection.parser_slot_id = String(data.get("parserSlotId", ""))
	selection.parser_instance_id = String(data.get("parserInstanceId", ""))
	selection.workshop_id = String(data.get("workshopId", ""))
	selection.workshop_version = int(data.get("workshopVersion", 0))
	selection.master_workshop_instance_id = String(data.get("masterWorkshopInstanceId", ""))
	selection.slave_workshop_instance_id = String(data.get("slaveWorkshopInstanceId", ""))
	var raw_skills: Variant = data.get("skillSelections", [])
	if raw_skills is Array:
		selection.skill_selections = raw_skills.duplicate(true)
	else:
		selection._source_errors.append("skillSelections must be an array")
	selection.expected_battle_duration_logical_milli = float(data.get("expectedBattleDurationLogicalMilli", 0.0))
	return selection

func to_data() -> Dictionary:
	return {
		"shipId": ship_id,
		"shipVersion": ship_version,
		"shipInstanceId": ship_instance_id,
		"deviceSelections": device_selections.duplicate(true),
		"parserId": parser_id,
		"parserVersion": parser_version,
		"parserSlotId": parser_slot_id,
		"parserInstanceId": parser_instance_id,
		"workshopId": workshop_id,
		"workshopVersion": workshop_version,
		"masterWorkshopInstanceId": master_workshop_instance_id,
		"slaveWorkshopInstanceId": slave_workshop_instance_id,
		"skillSelections": skill_selections.duplicate(true),
		"expectedBattleDurationLogicalMilli": expected_battle_duration_logical_milli
	}

func validate() -> PackedStringArray:
	var errors := _source_errors.duplicate()
	if ship_id.strip_edges().is_empty() or ship_version <= 0: errors.append("a versioned ship selection is required")
	if parser_id.strip_edges().is_empty() or parser_version <= 0 or parser_slot_id.strip_edges().is_empty(): errors.append("a versioned universal parser and its slot are required")
	if workshop_id.strip_edges().is_empty() or workshop_version <= 0: errors.append("a versioned workshop combination is required")
	if has_owned_instance_selection() and (ship_instance_id == "" or parser_instance_id == "" or master_workshop_instance_id == "" or slave_workshop_instance_id == "" or master_workshop_instance_id == slave_workshop_instance_id): errors.append("owned Hangar selection requires distinct exact ship/parser/Master/Slave instance IDs")
	if not is_finite(expected_battle_duration_logical_milli) or expected_battle_duration_logical_milli <= 0.0: errors.append("expected battle duration must be finite and positive")
	var slots := {}
	for raw in device_selections:
		if not (raw is Dictionary):
			errors.append("each production device selection must be a dictionary")
			continue
		var slot := String(raw.get("slotId", "")).strip_edges()
		var device_id := String(raw.get("definitionId", "")).strip_edges()
		var version := int(raw.get("definitionVersion", 0))
		if slot.is_empty() or slots.has(slot) or slot == parser_slot_id:
			errors.append("production device slots must be non-empty, unique, and distinct from parser slot")
		else:
			slots[slot] = true
		if device_id.is_empty() or version <= 0: errors.append("each production device must identify an exact definition version")
	var order_keys := {}
	for raw in skill_selections:
		if not (raw is Dictionary):
			errors.append("each skill selection must be a dictionary")
			continue
		var key := String(raw.get("orderDefinitionKey", "")).strip_edges()
		var skill_id := String(raw.get("skillId", "")).strip_edges()
		if key.is_empty() or order_keys.has(key): errors.append("skill order keys must be non-empty and unique")
		else: order_keys[key] = true
		if skill_id.is_empty() or int(raw.get("definitionVersion", 0)) <= 0: errors.append("each skill must identify an exact definition version")
		if String(raw.get("controlArea", "")).strip_edges().is_empty(): errors.append("each skill must select a control area")
	return errors

func has_owned_instance_selection() -> bool:
	return not ship_instance_id.is_empty() or not parser_instance_id.is_empty() or not master_workshop_instance_id.is_empty() or not slave_workshop_instance_id.is_empty()
