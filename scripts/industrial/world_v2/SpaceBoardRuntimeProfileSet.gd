extends RefCounted
class_name SpaceBoardRuntimeProfileSet
## Routes each frozen Board Assignment to the subsystem that actually consumes its
## runtime profile. This is a profile manifest, not a rule interpreter.

static func build(
	assignment_snapshot: Dictionary,
	jar_world_options: Dictionary,
	device_selections: Array,
	order_bindings: Array,
	workshop_selection: Dictionary
) -> Dictionary:
	if assignment_snapshot.is_empty() or jar_world_options.is_empty() or workshop_selection.is_empty():
		return {}
	var board: Dictionary = assignment_snapshot.get("boardDefinition", {})
	var assignments: Variant = assignment_snapshot.get("assignments", null)
	if not (assignments is Array) or String(board.get("boardId", "")) != String(assignment_snapshot.get("boardId", "")):
		return {}
	var entries: Array[Dictionary] = []
	var seen_slots := {}
	for assignment in assignments:
		if not (assignment is Dictionary):
			return {}
		var slot_id := String(assignment.get("slotId", ""))
		var kind := String(assignment.get("componentKind", ""))
		var instance_id := String(assignment.get("ownedInstanceId", ""))
		if slot_id.is_empty() or instance_id.is_empty() or seen_slots.has(slot_id) or String(assignment.get("definitionId", "")).is_empty() or int(assignment.get("definitionVersion", 0)) <= 0 or int(assignment.get("sourceRevision", 0)) <= 0:
			return {}
		seen_slots[slot_id] = true
		var consumer := ""
		var runtime_profile: Dictionary = {}
		var matched_count := 0
		match kind:
			"workshop":
				consumer = "jar_core.workshop"
				for workshop in jar_world_options.get("workshops", []):
					if workshop is Dictionary and String(workshop.get("boardSlotId", "")) == slot_id:
						matched_count += 1
						runtime_profile = workshop.duplicate(true)
				if matched_count != 1:
					return {}
				var role_id := String(assignment.get("roleId", ""))
				var owned_key := "masterWorkshopInstance" if role_id == "master" else ("slaveWorkshopInstance" if role_id == "slave" else "")
				var definition_key := "masterWorkshopDefinitionId" if role_id == "master" else ("slaveWorkshopDefinitionId" if role_id == "slave" else "")
				var version_key := "masterWorkshopDefinitionVersion" if role_id == "master" else ("slaveWorkshopDefinitionVersion" if role_id == "slave" else "")
				var workshop_owned: Variant = workshop_selection.get(owned_key, null)
				if owned_key.is_empty() or not _owned_instance_matches(workshop_owned, assignment):
					return {}
				if String(workshop_selection.get(definition_key, "")) != String(assignment.get("definitionId", "")) or int(workshop_selection.get(version_key, 0)) != int(assignment.get("definitionVersion", 0)):
					return {}
				if runtime_profile.is_empty():
					return {}
				var core_rules: Dictionary = jar_world_options.get("boardRuleProfile", {})
				var core_fingerprint := String(core_rules.get("fingerprint", ""))
				if core_fingerprint.is_empty():
					return {}
				runtime_profile["coreRuleProfileFingerprint"] = core_fingerprint
			"ore_parser":
				consumer = "space.parser"
				for device in device_selections:
					if device is Dictionary and String(device.get("slotId", "")) == slot_id and String(device.get("deviceKind", "")) == "ore_parser":
						matched_count += 1
						var parser: Variant = device.get("oreParserProfile", null)
						if parser is Dictionary and _device_identity_matches(device, assignment) and _parser_profile_matches(parser, assignment):
							runtime_profile = parser.duplicate(true)
				if matched_count != 1 or runtime_profile.is_empty():
					return {}
			"skill":
				consumer = "space.skill"
				var skill_profile_found := false
				for binding in order_bindings:
					if binding is Dictionary and String(binding.get("orderDefinitionKey", "")) == slot_id:
						matched_count += 1
						if not _skill_identity_matches(binding, assignment):
							return {}
						var jar_order: Variant = binding.get("jarOrder", null)
						var skill_control: Variant = binding.get("skillControl", null)
						var benefit_profile: Variant = binding.get("benefitProfile", null)
						var effect_binding: Variant = binding.get("effectBinding", null)
						if not (jar_order is Dictionary) or not (skill_control is Dictionary) or not (benefit_profile is Dictionary) or not (effect_binding is Dictionary) or effect_binding.is_empty():
							return {}
						runtime_profile = {
							"jarOrder": jar_order.duplicate(true),
							"skillControl": skill_control.duplicate(true),
							"benefitProfile": benefit_profile.duplicate(true),
							"effectBinding": effect_binding.duplicate(true)
						}
						skill_profile_found = true
						break
				if matched_count != 1 or not skill_profile_found:
					return {}
			"production_device":
				consumer = "space.production_device"
				var device_profile_found := false
				for device in device_selections:
					if device is Dictionary and String(device.get("slotId", "")) == slot_id and String(device.get("deviceKind", "")) != "ore_parser":
						matched_count += 1
						var device_profile: Variant = device.get("deviceRuntimeProfile", null)
						if device_profile is Dictionary and _device_identity_matches(device, assignment):
							runtime_profile = device_profile.duplicate(true)
							device_profile_found = true
				if matched_count != 1 or not device_profile_found:
					return {}
			_:
				return {}
		var source := {
			"slotId": slot_id,
			"componentKind": kind,
			"ownedInstanceId": instance_id,
			"definitionId": String(assignment.get("definitionId", "")),
			"definitionVersion": int(assignment.get("definitionVersion", 0)),
			"sourceRevision": int(assignment.get("sourceRevision", 0))
		}
		if assignment.has("roleId"):
			source["roleId"] = String(assignment.get("roleId", ""))
		if assignment.has("controlArea"):
			source["controlArea"] = String(assignment.get("controlArea", ""))
		var profile_fingerprint := _fingerprint(runtime_profile)
		if profile_fingerprint.is_empty():
			return {}
		entries.append({
			"consumer": consumer,
			"source": source,
			"profileFingerprint": profile_fingerprint
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("source", {}).get("slotId", "")) < String(b.get("source", {}).get("slotId", ""))
	)
	var result := {
		"schemaVersion": 1,
		"boardId": String(assignment_snapshot.get("boardId", "")),
		"boardDefinitionVersion": int(assignment_snapshot.get("definitionVersion", 0)),
		"assignmentFingerprint": String(assignment_snapshot.get("assignmentFingerprint", "")),
		"entries": entries
	}
	result["fingerprint"] = _fingerprint(result)
	return result

static func validate(source: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var supplied: Variant = source.get("boardRuntimeProfileSet", null)
	if not (supplied is Dictionary):
		errors.append("boardRuntimeProfileSet is required for an owned Board loadout")
		return errors
	var assignment: Variant = source.get("boardAssignmentSnapshot", null)
	var jar_options: Variant = source.get("jarWorldOptions", null)
	var devices: Variant = source.get("productionDeviceSelections", null)
	var orders: Variant = source.get("selectedOrderBindings", null)
	var workshop_selection: Variant = source.get("workshopCombinationSelection", null)
	if not (assignment is Dictionary) or not (jar_options is Dictionary) or not (devices is Array) or not (orders is Array) or not (workshop_selection is Dictionary):
		errors.append("Board Runtime Profile Set requires exact assignment, workshop, device, and skill profile collections")
		return errors
	var expected := build(assignment, jar_options, devices, orders, workshop_selection)
	if expected.is_empty():
		errors.append("Board Runtime Profile Set could not resolve every installed slot to its real consumer profile")
		return errors
	if JSON.stringify(_canonicalize(supplied)) != JSON.stringify(_canonicalize(expected)):
		errors.append("Board Runtime Profile Set differs from the frozen consumer profiles or exact assignments")
	return errors

static func _owned_instance_matches(raw: Variant, assignment: Dictionary) -> bool:
	if not (raw is Dictionary):
		return false
	return (
		String(raw.get("instanceId", "")) == String(assignment.get("ownedInstanceId", ""))
		and String(raw.get("definitionId", "")) == String(assignment.get("definitionId", ""))
		and int(raw.get("definitionVersion", 0)) == int(assignment.get("definitionVersion", 0))
		and int(raw.get("progressionRevision", 0)) == int(assignment.get("sourceRevision", 0))
	)

static func _device_identity_matches(device: Dictionary, assignment: Dictionary) -> bool:
	return (
		String(device.get("definitionId", "")) == String(assignment.get("definitionId", ""))
		and int(device.get("definitionVersion", 0)) == int(assignment.get("definitionVersion", 0))
		and _owned_instance_matches(device.get("ownedInstance", null), assignment)
	)

static func _parser_profile_matches(profile: Dictionary, assignment: Dictionary) -> bool:
	return (
		String(profile.get("parserId", "")) == String(assignment.get("definitionId", ""))
		and int(profile.get("definitionVersion", 0)) == int(assignment.get("definitionVersion", 0))
		and _owned_instance_matches(profile.get("ownedInstance", null), assignment)
	)

static func _skill_identity_matches(binding: Dictionary, assignment: Dictionary) -> bool:
	var control: Variant = binding.get("skillControl", null)
	return (
		String(binding.get("skillDefinitionId", "")) == String(assignment.get("definitionId", ""))
		and int(binding.get("skillDefinitionVersion", 0)) == int(assignment.get("definitionVersion", 0))
		and _owned_instance_matches(binding.get("ownedInstance", null), assignment)
		and control is Dictionary
		and String(control.get("area", "")) == String(assignment.get("controlArea", ""))
	)

static func _fingerprint(value: Dictionary) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update(JSON.stringify(_canonicalize(value)).to_utf8_buffer())
	return hashing.finish().hex_encode()

static func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
		var result := {}
		for key in keys:
			result[key] = _canonicalize(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_canonicalize(item))
		return result
	return value
