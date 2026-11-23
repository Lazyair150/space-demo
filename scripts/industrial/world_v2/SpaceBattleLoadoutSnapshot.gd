extends RefCounted
class_name SpaceBattleLoadoutSnapshot
## Immutable-by-interface snapshot of the four player-authored pre-battle build dimensions.
## Mutable source dictionaries are deep-copied on creation and on every read.

const CURRENT_SCHEMA_VERSION: int = 2

var _data: Dictionary = {}

static func create(source: Dictionary) -> SpaceBattleLoadoutSnapshot:
	var staged := source.duplicate(true)
	var fingerprint := compute_fingerprint(staged)
	if staged.has("loadoutFingerprint") and String(staged["loadoutFingerprint"]) != fingerprint:
		push_error("Space battle loadout fingerprint does not match its contents")
		return null
	staged["loadoutFingerprint"] = fingerprint
	var errors := validate_data(staged)
	if not errors.is_empty():
		push_error("Space battle loadout rejected: " + "; ".join(errors))
		return null
	var snapshot := SpaceBattleLoadoutSnapshot.new()
	snapshot._data = staged
	return snapshot

## Preferred Hangar construction path for the required universal ore parser.
## The exact catalog version is materialized into the device slot before the full
## immutable loadout is fingerprinted and validated.
static func create_with_ore_parser(
	source: Dictionary,
	parser_catalog: SpaceOreParserCatalog,
	parser_id: String,
	parser_version: int,
	parser_slot_id: String
) -> SpaceBattleLoadoutSnapshot:
	if parser_catalog == null:
		return null
	var staged := source.duplicate(true)
	var jar_options: Variant = staged.get("jarWorldOptions", null)
	if not (jar_options is Dictionary) or not (jar_options.get("shapes", null) is Array):
		return null
	var devices: Variant = staged.get("productionDeviceSelections", null)
	if not (devices is Array):
		return null
	var used_slots := {}
	for raw_device in devices:
		if not (raw_device is Dictionary):
			return null
		var slot_id := String(raw_device.get("slotId", ""))
		if slot_id.is_empty() or used_slots.has(slot_id) or String(raw_device.get("deviceKind", "")) == "ore_parser":
			push_error("Loadout builder requires unique non-parser slots and exactly one catalog-selected ore parser")
			return null
		used_slots[slot_id] = true
	if used_slots.has(parser_slot_id):
		push_error("Ore parser slot collides with another selected production device")
		return null
	var parser_selection := parser_catalog.create_device_selection(
		parser_id,
		parser_version,
		parser_slot_id,
		jar_options.shapes
	)
	if parser_selection.is_empty() or not parser_catalog.validate_device_selection(
		parser_selection,
		parser_slot_id,
		jar_options.shapes
	).is_empty():
		return null
	devices.append(parser_selection)
	staged["productionDeviceSelections"] = devices
	return create(staged)

static func compute_fingerprint(source: Dictionary) -> String:
	var canonical_source := source.duplicate(true)
	canonical_source.erase("loadoutFingerprint")
	var canonical_json := JSON.stringify(_canonicalize(canonical_source))
	var hasher := HashingContext.new()
	if hasher.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hasher.update(canonical_json.to_utf8_buffer())
	return hasher.finish().hex_encode()

static func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
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


static func _validate_board_assignment_snapshot(source: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var snapshot: Variant = source.get("boardAssignmentSnapshot", null)
	if not (snapshot is Dictionary):
		errors.append("boardAssignmentSnapshot must be a dictionary")
		return errors
	if int(snapshot.get("schemaVersion", 0)) != 1 or _required_text(snapshot, "assignmentFingerprint").is_empty():
		errors.append("boardAssignmentSnapshot requires schema version and assignment fingerprint")
	var fingerprint_payload: Dictionary = snapshot.duplicate(true)
	var supplied_fingerprint := String(fingerprint_payload.get("assignmentFingerprint", ""))
	fingerprint_payload.erase("assignmentFingerprint")
	var assignment_hasher := HashingContext.new()
	assignment_hasher.start(HashingContext.HASH_SHA256)
	assignment_hasher.update(JSON.stringify(fingerprint_payload).to_utf8_buffer())
	if supplied_fingerprint.is_empty() or assignment_hasher.finish().hex_encode() != supplied_fingerprint:
		errors.append("boardAssignmentSnapshot fingerprint does not match its canonical content")
	var board: Variant = snapshot.get("boardDefinition", null)
	if not (board is Dictionary):
		errors.append("boardAssignmentSnapshot must freeze its Board Definition")
		return errors
	if _required_text(board, "boardId") != _required_text(snapshot, "boardId") or int(board.get("definitionVersion", 0)) != int(snapshot.get("definitionVersion", 0)):
		errors.append("board assignment and Board Definition identities differ")
	var slots: Variant = board.get("slots", null)
	var assignments: Variant = snapshot.get("assignments", null)
	if not (slots is Array) or not (assignments is Array):
		errors.append("board assignment requires slot and assignment arrays")
		return errors
	var slot_index := {}
	var master_slot_id := ""
	var slave_slot_id := ""
	var parser_slot_id := ""
	var master_count := 0
	var slave_count := 0
	var parser_count := 0
	for raw_slot in slots:
		if not (raw_slot is Dictionary):
			errors.append("Board Definition contains an invalid slot")
			continue
		var slot_id := _required_text(raw_slot, "slotId")
		if slot_id.is_empty() or slot_index.has(slot_id):
			errors.append("Board Definition slot identity is empty or duplicated")
		else:
			slot_index[slot_id] = raw_slot
		var component_kind := String(raw_slot.get("componentKind", ""))
		var role_id := String(raw_slot.get("roleId", "none"))
		if component_kind == "workshop" and role_id == "master":
			master_count += 1
			master_slot_id = slot_id
		elif component_kind == "workshop" and role_id == "slave":
			slave_count += 1
			slave_slot_id = slot_id
		elif component_kind == "ore_parser":
			parser_count += 1
			parser_slot_id = slot_id
	if master_count != 1 or slave_count != 1 or parser_count != 1:
		errors.append("frozen board must contain exactly one Master, one Slave, and one parser position")
	var seen_slots := {}
	var seen_instances := {}
	for raw_entry in assignments:
		if not (raw_entry is Dictionary):
			errors.append("Board Assignment entry must be a dictionary")
			continue
		var slot_id := _required_text(raw_entry, "slotId")
		var instance_id := _required_text(raw_entry, "ownedInstanceId")
		if not slot_index.has(slot_id) or seen_slots.has(slot_id) or instance_id.is_empty() or seen_instances.has(instance_id):
			errors.append("Board Assignment contains an unknown slot or duplicate identity")
			continue
		seen_slots[slot_id] = true
		seen_instances[instance_id] = true
		var slot: Dictionary = slot_index[slot_id]
		if _required_text(raw_entry, "componentKind") != _required_text(slot, "componentKind"):
			errors.append("Board Assignment component kind differs from slot compatibility")
		if String(slot.get("componentKind", "")) == "workshop" and _required_text(raw_entry, "roleId") != _required_text(slot, "roleId"):
			errors.append("Board Assignment workshop role differs from its position")
		if String(slot.get("componentKind", "")) == "skill" and _required_text(raw_entry, "controlArea") != _required_text(slot, "controlArea"):
			errors.append("Board Assignment skill control area differs from its order position")
		if _required_text(raw_entry, "definitionId").is_empty() or int(raw_entry.get("definitionVersion", 0)) <= 0:
			errors.append("Board Assignment must retain exact component Definition identity/version")
		if int(raw_entry.get("sourceRevision", 0)) <= 0:
			errors.append("Board Assignment must retain exact Owned Instance progression revision")
		var revision_found := false
		for owned_snapshot in source.get("ownedInstanceSnapshots", []):
			if owned_snapshot is Dictionary and _required_text(owned_snapshot, "instanceId") == instance_id:
				revision_found = int(owned_snapshot.get("progressionRevision", 0)) == int(raw_entry.get("sourceRevision", 0))
				break
		if not revision_found:
			errors.append("Board Assignment progression revision differs from frozen Owned Instance snapshot")
	for slot_id in slot_index:
		var slot: Dictionary = slot_index[slot_id]
		if bool(slot.get("required", false)) and not seen_slots.has(slot_id):
			errors.append("required Board Slot is empty: " + slot_id)
	var expected_count := 3
	var devices: Variant = source.get("productionDeviceSelections", [])
	var orders: Variant = source.get("selectedOrderBindings", [])
	if devices is Array:
		for device in devices:
			if device is Dictionary and String(device.get("deviceKind", "")) != "ore_parser":
				expected_count += 1
	if orders is Array:
		expected_count += orders.size()
	if assignments.size() != expected_count:
		errors.append("Board Assignment count differs from frozen runtime projection")
	var assignment_by_slot := {}
	for raw_entry in assignments:
		if raw_entry is Dictionary:
			assignment_by_slot[String(raw_entry.get("slotId", ""))] = raw_entry
	var workshop: Variant = source.get("workshopCombinationSelection", {})
	if workshop is Dictionary:
		for pair in [{"slotId": master_slot_id, "key": "masterWorkshopInstance"}, {"slotId": slave_slot_id, "key": "slaveWorkshopInstance"}]:
			var frozen_instance: Variant = workshop.get(String(pair.key), null)
			var assigned: Variant = assignment_by_slot.get(String(pair.slotId), null)
			if not (frozen_instance is Dictionary) or not (assigned is Dictionary) or _required_text(frozen_instance, "instanceId") != _required_text(assigned, "ownedInstanceId"):
				errors.append("frozen Master/Slave selection differs from its Board Assignment")
	if devices is Array:
		for device in devices:
			if not (device is Dictionary):
				continue
			var slot_id := String(device.get("slotId", ""))
			var assigned: Variant = assignment_by_slot.get(slot_id, null)
			var owned_device: Variant = device.get("ownedInstance", null)
			if not (assigned is Dictionary) or not (owned_device is Dictionary) or _required_text(assigned, "ownedInstanceId") != _required_text(owned_device, "instanceId"):
				errors.append("frozen production-device selection differs from its Board Assignment: " + slot_id)
	if orders is Array:
		for order in orders:
			if not (order is Dictionary):
				continue
			var slot_id := String(order.get("orderDefinitionKey", ""))
			var slot: Dictionary = slot_index.get(slot_id, {})
			var assigned: Variant = assignment_by_slot.get(slot_id, null)
			var owned_skill: Variant = order.get("ownedInstance", null)
			if String(slot.get("componentKind", "")) != "skill" or not (assigned is Dictionary) or not (owned_skill is Dictionary) or _required_text(assigned, "ownedInstanceId") != _required_text(owned_skill, "instanceId"):
				errors.append("frozen skill selection differs from its order-board assignment: " + slot_id)
			var skill_control: Variant = order.get("skillControl", {})
			if skill_control is Dictionary and String(slot.get("controlArea", "")) != String(skill_control.get("area", "")):
				errors.append("frozen skill control area differs from its order-board slot: " + slot_id)
	if devices is Array:
		var parser_found := false
		for device in devices:
			if device is Dictionary and String(device.get("deviceKind", "")) == "ore_parser":
				parser_found = true
				var assigned: Variant = assignment_by_slot.get(parser_slot_id, null)
				var owned_parser: Variant = device.get("ownedInstance", null)
				if String(device.get("slotId", "")) != parser_slot_id or not (assigned is Dictionary) or not (owned_parser is Dictionary) or _required_text(assigned, "ownedInstanceId") != _required_text(owned_parser, "instanceId"):
					errors.append("frozen parser selection differs from its decomposition-board assignment")
		if not parser_found:
			errors.append("frozen Board Assignment has no parser selection")
	return errors


static func _validate_board_rule_profile(source: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var profile: Variant = source.get("boardRuleProfile", null)
	var assignment: Dictionary = source.get("boardAssignmentSnapshot", {})
	if not (profile is Dictionary) or assignment.is_empty():
		errors.append("boardRuleProfile requires a matching Board Assignment snapshot")
		return errors
	if int(profile.get("schemaVersion", 0)) != 1 or _required_text(profile, "fingerprint").is_empty():
		errors.append("boardRuleProfile requires schema version and fingerprint")
	if _required_text(profile, "boardId") != _required_text(assignment, "boardId") or int(profile.get("boardDefinitionVersion", 0)) != int(assignment.get("definitionVersion", 0)):
		errors.append("boardRuleProfile Board identity differs from Board Assignment")
	if _required_text(profile, "assignmentFingerprint") != _required_text(assignment, "assignmentFingerprint"):
		errors.append("boardRuleProfile was not resolved from the frozen Board Assignment revision")
	var payload: Dictionary = profile.duplicate(true)
	var supplied := String(payload.get("fingerprint", ""))
	payload.erase("fingerprint")
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(JSON.stringify(_canonicalize(payload)).to_utf8_buffer())
	if supplied.is_empty() or hashing.finish().hex_encode() != supplied:
		errors.append("boardRuleProfile fingerprint does not match its canonical contributions")
	var assignments_by_slot := {}
	for entry in assignment.get("assignments", []):
		if entry is Dictionary:
			assignments_by_slot[String(entry.get("slotId", ""))] = entry
	var contributions: Variant = profile.get("contributions", null)
	if not (contributions is Array):
		errors.append("boardRuleProfile contributions must be an array")
		return errors
	for contribution in contributions:
		if not (contribution is Dictionary):
			errors.append("boardRuleProfile contains an invalid contribution")
			continue
		var contribution_source: Variant = contribution.get("source", null)
		if not (contribution_source is Dictionary):
			errors.append("rule contribution source provenance is required")
			continue
		var slot_id := _required_text(contribution_source, "slotId")
		if not assignments_by_slot.has(slot_id):
			errors.append("rule contribution source references a slot with no installed component")
			continue
		var installed: Dictionary = assignments_by_slot[slot_id]
		if _required_text(contribution_source, "sourceInstanceId") != _required_text(installed, "ownedInstanceId"):
			errors.append("rule contribution source instance differs from installed Owned Instance")
		if _required_text(contribution_source, "definitionId") != _required_text(installed, "definitionId") or int(contribution_source.get("definitionVersion", 0)) != int(installed.get("definitionVersion", 0)):
			errors.append("rule contribution source Definition identity/version differs from Board Assignment")
		if int(contribution_source.get("sourceRevision", 0)) != int(installed.get("sourceRevision", 0)):
			errors.append("rule contribution progression revision differs from its Board Assignment")
		if _required_text(contribution_source, "sourceKind") != "installed-component":
			errors.append("rule contribution source kind must identify an installed component")
		var owned_revision_found := false
		for raw_owned in source.get("ownedInstanceSnapshots", []):
			if raw_owned is Dictionary and _required_text(raw_owned, "instanceId") == _required_text(contribution_source, "sourceInstanceId"):
				owned_revision_found = int(raw_owned.get("progressionRevision", 0)) == int(contribution_source.get("sourceRevision", 0))
				break
		if not owned_revision_found:
			errors.append("rule contribution source revision differs from the frozen Owned Instance progression revision")
		if _required_text(contribution, "scope") != "workshop" or String(installed.get("componentKind", "")) != "workshop":
			errors.append("this Core ingress revision accepts only workshop-scoped contributions from workshop Board Slots")
		if _required_text(contribution, "ruleId").is_empty() or int(contribution.get("ruleVersion", 0)) != 1 or _required_text(contribution, "target").is_empty():
			errors.append("rule contribution requires a supported exact rule identity/version and target")
	return errors

static func validate_data(source: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if int(source.get("schemaVersion", 0)) != CURRENT_SCHEMA_VERSION:
		errors.append("unsupported schemaVersion")
	if _required_text(source, "shipWorldId").is_empty():
		errors.append("shipWorldId is required")
	if _required_text(source, "loadoutId").is_empty():
		errors.append("loadoutId is required")
	if _required_text(source, "loadoutFingerprint").is_empty():
		errors.append("loadoutFingerprint is required")
	if int(source.get("loadoutVersion", 0)) <= 0:
		errors.append("loadoutVersion must be positive")

	var ship: Variant = source.get("shipSelection", null)
	if not (ship is Dictionary):
		errors.append("shipSelection must be a dictionary")
	else:
		if _required_text(ship, "definitionId").is_empty() or int(ship.get("definitionVersion", 0)) <= 0:
			errors.append("shipSelection must identify a versioned ship definition")

	var devices: Variant = source.get("productionDeviceSelections", null)
	if not (devices is Array):
		errors.append("productionDeviceSelections must be an array")
	elif devices.is_empty():
		errors.append("at least one production device selection is required")
	else:
		var slots := {}
		for raw_device in devices:
			if not (raw_device is Dictionary):
				errors.append("production device selection must be a dictionary")
				continue
			var device: Dictionary = raw_device
			var slot_id := _required_text(device, "slotId")
			if slot_id.is_empty() or slots.has(slot_id):
				errors.append("production device slotId is missing or duplicated")
			else:
				slots[slot_id] = true
			if _required_text(device, "definitionId").is_empty() or int(device.get("definitionVersion", 0)) <= 0:
				errors.append("production device must identify a versioned definition")

	var workshop: Variant = source.get("workshopCombinationSelection", null)
	if not (workshop is Dictionary):
		errors.append("workshopCombinationSelection must be a dictionary")
	else:
		if _required_text(workshop, "definitionId").is_empty() or int(workshop.get("definitionVersion", 0)) <= 0:
			errors.append("workshop combination must identify a versioned definition")
		if source.has("progressionOwnerPlayerId"):
			var master_instance: Variant = workshop.get("masterWorkshopInstance", null)
			var slave_instance: Variant = workshop.get("slaveWorkshopInstance", null)
			if not (master_instance is Dictionary) or not (slave_instance is Dictionary):
				errors.append("owned workshop positions must freeze both exact owned instances")
			elif _required_text(master_instance, "instanceId").is_empty() or _required_text(slave_instance, "instanceId").is_empty() or _required_text(master_instance, "instanceId") == _required_text(slave_instance, "instanceId"):
				errors.append("Master and Slave positions must contain two different owned instance identities")

	var jar_options: Variant = source.get("jarWorldOptions", null)
	if not (jar_options is Dictionary):
		errors.append("jarWorldOptions must be a fully materialized WorldV2Options dictionary")
	else:
		for required_key in ["shapes", "liquids", "producers", "workshops", "masterWorkshopName", "slaveWorkshopName"]:
			if not jar_options.has(required_key):
				errors.append("jarWorldOptions is missing " + required_key)
		var active_workshops: Variant = jar_options.get("workshops", null)
		if not (active_workshops is Array) or active_workshops.size() != 2:
			errors.append("jarWorldOptions must materialize exactly two player-selected workshop positions")
		elif String(jar_options.get("masterWorkshopName", "")) == String(jar_options.get("slaveWorkshopName", "")):
			errors.append("Master and Slave workspace positions require distinct Core role names")

	if source.has("boardAssignmentSnapshot"):
		errors.append_array(_validate_board_assignment_snapshot(source))
		errors.append_array(SpaceBoardRuntimeProfileSet.validate(source))
	if source.has("boardRuleProfile"):
		errors.append_array(_validate_board_rule_profile(source))
		var jar_profile: Variant = jar_options.get("boardRuleProfile", {}) if jar_options is Dictionary else {}
		var jar_assignment: Variant = jar_options.get("boardAssignmentSnapshot", {}) if jar_options is Dictionary else {}
		if not (jar_profile is Dictionary) or JSON.stringify(_canonicalize(jar_profile)) != JSON.stringify(_canonicalize(source.get("boardRuleProfile", {}))):
			errors.append("jarWorldOptions.boardRuleProfile must exactly match the root frozen Board rule profile")
		if not (jar_assignment is Dictionary) or JSON.stringify(_canonicalize(jar_assignment)) != JSON.stringify(_canonicalize(source.get("boardAssignmentSnapshot", {}))):
			errors.append("jarWorldOptions.boardAssignmentSnapshot must exactly match the root frozen Board Assignment")
	elif source.has("boardAssignmentSnapshot"):
		errors.append("boardAssignmentSnapshot requires its resolved boardRuleProfile")
	if source.has("assemblyBoard") and source.has("boardAssignmentSnapshot"):
		var assembly_board: Dictionary = source.get("assemblyBoard", {})
		var assignment_board: Dictionary = source.get("boardAssignmentSnapshot", {}).get("boardDefinition", {})
		if _required_text(assembly_board, "boardId") != _required_text(assignment_board, "boardId") or int(assembly_board.get("definitionVersion", 0)) != int(assignment_board.get("definitionVersion", 0)):
			errors.append("assemblyBoard and Board Assignment snapshot must freeze the same Board Definition version")

	if source.has("progressionOwnerPlayerId") or source.has("ownedInstanceSnapshots"):
		var referenced_ids := {}
		if ship is Dictionary and ship.get("ownedInstance", null) is Dictionary:
			referenced_ids[String(ship.ownedInstance.get("instanceId", ""))] = true
		if devices is Array:
			for device in devices:
				if device is Dictionary and device.get("ownedInstance", null) is Dictionary:
					referenced_ids[String(device.ownedInstance.get("instanceId", ""))] = true
		if workshop is Dictionary:
			for key in ["masterWorkshopInstance", "slaveWorkshopInstance"]:
				var workshop_instance: Variant = workshop.get(key, null)
				if workshop_instance is Dictionary:
					referenced_ids[String(workshop_instance.get("instanceId", ""))] = true
		var raw_order_bindings: Variant = source.get("selectedOrderBindings", [])
		if raw_order_bindings is Array:
			for order in raw_order_bindings:
				if order is Dictionary and order.get("ownedInstance", null) is Dictionary:
					referenced_ids[String(order.ownedInstance.get("instanceId", ""))] = true
		var owned_snapshot_ids := {}
		for raw_instance in source.get("ownedInstanceSnapshots", []):
			if raw_instance is Dictionary:
				owned_snapshot_ids[String(raw_instance.get("instanceId", ""))] = true
		if referenced_ids.size() != owned_snapshot_ids.size():
			errors.append("owned instance snapshots must exactly match the instances embedded in selected loadout slots")
		for instance_id in referenced_ids:
			if not owned_snapshot_ids.has(instance_id):
				errors.append("selected loadout slot references an instance missing from ownedInstanceSnapshots: " + String(instance_id))
	# The selected ore parser is part of the frozen pre-battle production-device build.
	# Its percentage is a parser attribute and scales that parser's own throughput;
	# it is not a per-shape output allocation.
	var ore_parser_count := 0
	var shape_set := {}
	if jar_options is Dictionary and jar_options.get("shapes", null) is Array:
		for raw_shape in jar_options.shapes:
			shape_set[String(raw_shape)] = true
	if devices is Array:
		for raw_device in devices:
			if not (raw_device is Dictionary) or String(raw_device.get("deviceKind", "")) != "ore_parser":
				continue
			ore_parser_count += 1
			var device: Dictionary = raw_device
			var parser: Variant = device.get("oreParserProfile", null)
			if not (parser is Dictionary):
				errors.append("selected ore parser must include oreParserProfile")
				continue
			if _required_text(parser, "parserId").is_empty() or int(parser.get("definitionVersion", 0)) <= 0:
				errors.append("oreParserProfile must identify a versioned parser definition")
			if _required_text(device, "definitionId") != _required_text(parser, "parserId") or int(device.get("definitionVersion", 0)) != int(parser.get("definitionVersion", 0)):
				errors.append("production device identity must match its oreParserProfile")
			var percentage: Variant = parser.get("productionPercentage", null)
			if typeof(percentage) != TYPE_INT or int(percentage) < 0 or int(percentage) > 100:
				errors.append("ore parser productionPercentage must be an integer from 0 to 100")
			var rates: Variant = parser.get("shapeProcessingRatePerSecond", null)
			var progress: Variant = parser.get("progressPerJarByShape", null)
			if not (rates is Dictionary) or not (progress is Dictionary):
				errors.append("ore parser must provide per-shape processing rates and progress thresholds")
				continue
			if rates.size() != shape_set.size() or progress.size() != shape_set.size():
				errors.append("ore parser must define every configured Jar shape exactly once")
			for shape in shape_set:
				if not rates.has(shape) or not progress.has(shape):
					errors.append("ore parser is missing shape configuration: " + String(shape))
					continue
				var rate: Variant = rates[shape]
				var threshold: Variant = progress[shape]
				if (typeof(rate) != TYPE_INT and typeof(rate) != TYPE_FLOAT) or not is_finite(float(rate)) or float(rate) < 0.0 or float(rate) > 1000000000.0:
					errors.append("ore parser shape rate is outside the supported fixed-point range: " + String(shape))
				if (typeof(threshold) != TYPE_INT and typeof(threshold) != TYPE_FLOAT) or not is_finite(float(threshold)) or float(threshold) <= 0.0 or float(threshold) > 1000000000.0 or round(float(threshold) * 1000000.0) < 1.0:
					errors.append("ore parser progress-per-Jar must be positive and representable in fixed-point: " + String(shape))
	if ore_parser_count != 1:
		errors.append("battle loadout must select exactly one universal ore parser")

	var orders: Variant = source.get("selectedOrderBindings", null)
	if not (orders is Array):
		errors.append("selectedOrderBindings must be an array")
	else:
		var order_keys := {}
		for raw_order in orders:
			if not (raw_order is Dictionary):
				errors.append("selected order binding must be a dictionary")
				continue
			var order: Dictionary = raw_order
			var order_key := _required_text(order, "orderDefinitionKey")
			if order_key.is_empty() or order_keys.has(order_key):
				errors.append("orderDefinitionKey is missing or duplicated")
			else:
				order_keys[order_key] = true

			var jar_order: Variant = order.get("jarOrder", null)
			var resolved_order_requirements: Array = []
			if not (jar_order is Dictionary):
				errors.append("selected order must contain jarOrder data")
			else:
				if jar_order.has("templateName"):
					var template_name := _required_text(jar_order, "templateName")
					if template_name.is_empty() or jar_order.has("type") or jar_order.has("requirements"):
						errors.append("template-backed Jar order must contain only a templateName, not copied type/requirements")
					var template_identity: Variant = order.get("jarOrderTemplate", null)
					if not (template_identity is Dictionary):
						errors.append("template-backed skill must freeze its exact template identity")
					elif _required_text(template_identity, "templateId").is_empty() or int(template_identity.get("templateVersion", 0)) <= 0 or _required_text(template_identity, "templateName") != template_name or ("%s@%d" % [_required_text(template_identity, "templateId"), int(template_identity.get("templateVersion", 0))]) != template_name:
						errors.append("frozen Core template identity must match the runtime templateName")
					var templates: Variant = jar_options.get("orderTemplates", []) if jar_options is Dictionary else []
					var matched_template: Dictionary = {}
					if templates is Array:
						for raw_template in templates:
							if raw_template is Dictionary and String(raw_template.get("name", "")) == template_name:
								matched_template = raw_template
								break
					if matched_template.is_empty():
							errors.append("Jar order templateName must resolve in frozen jarWorldOptions.orderTemplates")
					else:
						if not ["A", "B"].has(String(matched_template.get("type", ""))):
							errors.append("Core order template type must be A or B")
						var template_requirements: Variant = matched_template.get("requirements", null)
						if not (template_requirements is Array) or template_requirements.is_empty():
							errors.append("Core order template must contain non-empty requirements")
						elif template_requirements is Array:
							resolved_order_requirements = template_requirements
				else:
						errors.append("jarWorldOptions.orderTemplates must be an array")
				else:
					# Compatibility for legacy development bindings only.
					if not ["A", "B"].has(String(jar_order.get("type", ""))):
						errors.append("Jar order type must be A or B")
					var legacy_requirements: Variant = jar_order.get("requirements", null)
					if not (legacy_requirements is Array):
						errors.append("Jar order requirements must be an array")
					elif legacy_requirements.is_empty():
						errors.append("Jar order requirements must be non-empty")
					elif legacy_requirements is Array:
						resolved_order_requirements = legacy_requirements
				for raw_requirement in resolved_order_requirements:
					if not (raw_requirement is Dictionary):
						errors.append("Jar order requirement must be a dictionary")
						continue
					var requirement: Dictionary = raw_requirement
					if String(requirement.get("shape", "")).strip_edges().is_empty():
						errors.append("Jar order requirement must identify a shape")
				if int(jar_order.get("cooldownDurationLogicalMilli", -1)) < 0:
					errors.append("order cooldown cannot be negative")
				if not ["Active", "Passive"].has(String(jar_order.get("area", ""))):
					errors.append("order area must be Active or Passive")

			var presentation: Variant = order.get("presentation", {})
			if not (presentation is Dictionary):
				errors.append("order presentation metadata must be a dictionary")
			else:
				var primary_shape := String(presentation.get("primaryShape", "")).strip_edges()
				if not primary_shape.is_empty() and jar_order is Dictionary:
					var presentation_requirements: Variant = resolved_order_requirements
					var primary_shape_found := false
					if presentation_requirements is Array:
						for raw_requirement in presentation_requirements:
							if raw_requirement is Dictionary and String(raw_requirement.get("shape", "")) == primary_shape:
								primary_shape_found = true
								break
					if not primary_shape_found:
						errors.append("order primaryShape must be present in its Jar requirements")

			var skill_identity_present := order.has("skillDefinitionId") or order.has("skillDefinitionVersion")
			if skill_identity_present and (_required_text(order, "skillDefinitionId").is_empty() or int(order.get("skillDefinitionVersion", 0)) <= 0):
				errors.append("skill definition identity must be fully versioned")
			if order.has("skillControl"):
				var skill_control: Variant = order.get("skillControl")
				if not (skill_control is Dictionary):
					errors.append("skillControl must be a dictionary")
				else:
					var control_area := String(skill_control.get("area", ""))
					var activation_policy := String(skill_control.get("activationPolicy", ""))
					if not ["Active", "Passive"].has(control_area):
						errors.append("skill control area must be Active or Passive")
					if (control_area == "Active" and activation_policy != "Manual") or (control_area == "Passive" and activation_policy != "Automatic"):
						errors.append("skill activation policy must match its selected control area")

			var effect: Variant = order.get("effectBinding", null)
			var balance_report: Variant = order.get("balanceReport", null)
			if not (balance_report is Dictionary) or not bool(balance_report.get("valid", false)):
				errors.append("selected skill must include a valid benefit-to-Jar balance report")
			else:
				if float(balance_report.get("targetDifficulty", -1.0)) < 0.0 or float(balance_report.get("actualDifficulty", -1.0)) < 0.0:
					errors.append("balance report difficulty values must be non-negative")
				var breakdown: Variant = balance_report.get("costBreakdown", null)
				if not (breakdown is Dictionary):
					errors.append("balance report must include a cost breakdown")
				elif jar_order is Dictionary and not resolved_order_requirements.is_empty():
					var required_liquid_jars := 0
					for requirement in resolved_order_requirements:
						if requirement is Dictionary and not String(requirement.get("liquid", "")).strip_edges().is_empty():
							required_liquid_jars += 1
					if int(breakdown.get("jarCount", -1)) != resolved_order_requirements.size() or int(breakdown.get("liquidJarCount", -1)) != required_liquid_jars:
						errors.append("balance report cost breakdown does not match actual Jar requirements")
			var balance_context: Variant = order.get("balanceContext", null)
			if not (balance_context is Dictionary) or not bool(balance_context.get("valid", false)) or float(balance_context.get("expectedBattleDurationLogicalMilli", 0.0)) <= 0.0:
				errors.append("selected skill must include build-derived production/workshop difficulty context")
			var balance_profile: Variant = order.get("balanceProfile", null)
			if not (balance_profile is Dictionary) or _required_text(balance_profile, "profileId").is_empty() or int(balance_profile.get("profileVersion", 0)) <= 0:
				errors.append("selected skill must identify its balance profile version")

			if not (effect is Dictionary):
				errors.append("effectBinding must be a dictionary")
			else:
				if _required_text(effect, "effectDefinitionId").is_empty() or int(effect.get("effectDefinitionVersion", 0)) <= 0:
					errors.append("effectBinding must identify a versioned Space effect")
				if not (effect.get("effectParameters", {}) is Dictionary):
					errors.append("effectParameters must be a dictionary")

	if source.has("progressionOwnerPlayerId") or source.has("ownedInstanceSnapshots"):
		if _required_text(source, "progressionOwnerPlayerId").is_empty() or int(source.get("progressionStateRevision", 0)) <= 0:
			errors.append("owned loadout must identify its progression owner and state revision")
		var owned: Variant = source.get("ownedInstanceSnapshots", null)
		if not (owned is Array) or owned.is_empty():
			errors.append("owned loadout must freeze at least one owned instance snapshot")
		else:
			var owned_ids := {}
			for raw_instance in owned:
				if not (raw_instance is Dictionary):
					errors.append("owned instance snapshot must be a dictionary")
					continue
				var instance_id := _required_text(raw_instance, "instanceId")
				var kind := _required_text(raw_instance, "itemKind")
				if instance_id.is_empty() or owned_ids.has(instance_id):
					errors.append("owned instance snapshot IDs must be non-empty and unique")
				owned_ids[instance_id] = true
				if not SpaceOwnedProgressionInstance.ITEM_KINDS.has(kind):
					errors.append("owned instance snapshot has an unsupported item kind")
				if _required_text(raw_instance, "definitionId").is_empty() or int(raw_instance.get("definitionVersion", 0)) <= 0:
					errors.append("owned instance snapshot must identify an exact definition version")
				if int(raw_instance.get("level", 0)) <= 0 or int(raw_instance.get("experience", -1)) < 0 or int(raw_instance.get("progressionRevision", 0)) <= 0:
					errors.append("owned instance snapshot progression counters are invalid")
				var curve_id := _required_text(raw_instance, "growthCurveId")
				var curve_version := int(raw_instance.get("growthCurveVersion", 0))
				if (curve_id.is_empty() and curve_version != 0) or (not curve_id.is_empty() and curve_version <= 0):
					errors.append("owned instance snapshot growth curve provenance is inconsistent")
				if not (raw_instance.get("growthAttributes", null) is Dictionary):
					errors.append("owned instance snapshot growthAttributes must be a dictionary")
	return errors

func ship_world_id() -> String:
	return String(_data.get("shipWorldId", ""))

func loadout_id() -> String:
	return String(_data.get("loadoutId", ""))

func loadout_version() -> int:
	return int(_data.get("loadoutVersion", 0))

func loadout_fingerprint() -> String:
	return String(_data.get("loadoutFingerprint", ""))

func to_dictionary() -> Dictionary:
	return _data.duplicate(true)

func jar_world_options() -> Dictionary:
	return _data.get("jarWorldOptions", {}).duplicate(true)

func jar_world_options_json() -> String:
	return JSON.stringify(jar_world_options())

func selected_order_bindings() -> Array:
	return _data.get("selectedOrderBindings", []).duplicate(true)
func ore_parser_profile() -> Dictionary:
	for device in _data.get("productionDeviceSelections", []):
		if String(device.get("deviceKind", "")) == "ore_parser":
			return device.get("oreParserProfile", {}).duplicate(true)
	return {}


func order_definition_keys() -> PackedStringArray:
	var result := PackedStringArray()
	for order in _data.get("selectedOrderBindings", []):
		result.append(String(order.get("orderDefinitionKey", "")))
	return result

func order_presentation_metadata() -> Dictionary:
	var result := {}
	for order in _data.get("selectedOrderBindings", []):
		if not (order is Dictionary):
			continue
		var order_key := String(order.get("orderDefinitionKey", ""))
		var presentation: Variant = order.get("presentation", {})
		if order_key.is_empty() or not (presentation is Dictionary):
			continue
		var primary_shape := String(presentation.get("primaryShape", ""))
		if not primary_shape.is_empty():
			result[order_key] = {"primaryShape": primary_shape}
	return result


func resolve_order_binding(order_definition_key: String) -> Dictionary:
	for order in _data.get("selectedOrderBindings", []):
		if String(order.get("orderDefinitionKey", "")) == order_definition_key:
			return order.duplicate(true)
	return {}


static func _required_text(source: Dictionary, key: String) -> String:
	return String(source.get(key, "")).strip_edges()
