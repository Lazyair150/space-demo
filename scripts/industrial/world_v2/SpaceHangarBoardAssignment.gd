extends RefCounted
class_name SpaceHangarBoardAssignment
## Player-owned slot installation state. Board definitions describe positions only.

static func create_entry(slot: SpaceHangarBoardSlotDefinition, choice: Dictionary) -> Dictionary:
	if slot == null or choice.is_empty():
		return {}
	var instance_id := String(choice.get("instanceId", "")).strip_edges()
	var definition_id := String(choice.get("id", "")).strip_edges()
	var version := int(choice.get("version", 0))
	if instance_id.is_empty() or definition_id.is_empty() or version <= 0:
		return {}
	return {
		"slotId": String(slot.slot_id),
		"componentKind": slot.component_kind,
		"ownedInstanceId": instance_id,
		"definitionId": definition_id,
		"definitionVersion": version
	}

static func validate(board: SpaceHangarBoardDefinition, assignments: Dictionary, inventory: Dictionary, require_complete: bool = true) -> PackedStringArray:
	var errors := PackedStringArray()
	if board == null or not board.get_validation_errors().is_empty():
		errors.append("a valid Board Definition is required")
		return errors
	var slots := board.build_slot_index()
	var used_instances := {}
	for raw_slot_id in assignments:
		var slot_id := String(raw_slot_id)
		var entry: Variant = assignments[raw_slot_id]
		if not (entry is Dictionary):
			errors.append("assignment entry must be a dictionary: " + slot_id)
			continue
		if not slots.has(slot_id):
			errors.append("assignment references an unknown Board Slot: " + slot_id)
			continue
		var slot: Dictionary = slots[slot_id]
		if String(entry.get("slotId", "")) != slot_id:
			errors.append("assignment key and slot identity differ: " + slot_id)
		if String(entry.get("componentKind", "")) != String(slot.componentKind):
			errors.append("assignment component kind is incompatible with slot: " + slot_id)
		var instance_id := String(entry.get("ownedInstanceId", ""))
		if instance_id.is_empty() or used_instances.has(instance_id):
			errors.append("owned instance is empty or installed more than once: " + instance_id)
		used_instances[instance_id] = true
		var choice := _find_inventory_instance(inventory, instance_id)
		if choice.is_empty():
			errors.append("assigned instance is not present in the player's owned inventory: " + instance_id)
			continue
		if String(choice.get("id", "")) != String(entry.get("definitionId", "")) or int(choice.get("version", 0)) != int(entry.get("definitionVersion", 0)):
			errors.append("assignment exact Definition identity/version does not match owned instance: " + instance_id)
		if not _kind_matches(String(slot.componentKind), String(choice.get("itemKind", _kind_for_slot(String(slot.componentKind))))):
			errors.append("owned instance item kind does not match slot: " + slot_id)
	for slot_id in slots:
		var slot: Dictionary = slots[slot_id]
		if require_complete and bool(slot.get("required", false)) and not assignments.has(slot_id):
			errors.append("required Board Slot is empty: " + slot_id)
	return errors

static func build_snapshot(board: SpaceHangarBoardDefinition, assignments: Dictionary) -> Dictionary:
	if board == null or not board.get_validation_errors().is_empty():
		return {}
	var keys: Array = assignments.keys()
	keys.sort()
	var canonical: Array[Dictionary] = []
	for key in keys:
		var entry: Dictionary = assignments[key].duplicate(true)
		canonical.append(entry)
	var payload := {
		"schemaVersion": 1,
		"boardId": String(board.board_id),
		"definitionVersion": board.definition_version,
		"boardDefinition": board.build_frozen_snapshot(),
		"assignments": canonical
	}
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(JSON.stringify(payload).to_utf8_buffer())
	payload["assignmentFingerprint"] = hashing.finish().hex_encode()
	return payload

static func _find_inventory_instance(inventory: Dictionary, instance_id: String) -> Dictionary:
	for key in ["parserChoices", "deviceChoices", "workshopInstanceChoices", "skillChoices"]:
		var values: Variant = inventory.get(key, [])
		if not (values is Array):
			continue
		for value in values:
			if value is Dictionary and String(value.get("instanceId", "")) == instance_id:
				var result: Dictionary = value.duplicate(true)
				result["itemKind"] = _kind_for_collection(key)
				return result
	return {}

static func _kind_for_collection(key: String) -> String:
	match key:
		"parserChoices": return "ore_parser"
		"deviceChoices": return "production_device"
		"workshopInstanceChoices": return "workshop"
		"skillChoices": return "skill"
	return ""

static func _kind_for_slot(kind: String) -> String:
	return kind

static func _kind_matches(slot_kind: String, item_kind: String) -> bool:
	return slot_kind == item_kind
