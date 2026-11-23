extends RefCounted
class_name SpaceHangarOwnedLoadoutAssembler
## Owned-instance-only production assembly. The legacy definition assembler remains
## available for development probes; this path requires exact player ownership for every slot.

static func assemble(
	identity: Dictionary,
	selection: Dictionary,
	bundle: SpaceHangarCatalogBundle,
	progression: SpacePlayerProgressionState
) -> SpaceBattleLoadoutSnapshot:
	if bundle == null or progression == null or not progression.get_validation_errors().is_empty():
		return _reject("owned loadout requires a valid catalog bundle and player progression aggregate")
	for key in ["shipId", "shipVersion", "shipInstanceId", "parserId", "parserVersion", "parserSlotId", "parserInstanceId", "workshopId", "workshopVersion", "masterWorkshopInstanceId", "slaveWorkshopInstanceId", "skillSelections", "deviceSelections", "expectedBattleDurationLogicalMilli"]:
		if not selection.has(key):
			return _reject("owned selection is missing " + key)
	var board_assignment_snapshot: Dictionary = selection.get("boardAssignments", {})
	if not board_assignment_snapshot.is_empty():
		var assignment_error := _validate_board_assignment_snapshot(board_assignment_snapshot, progression, selection)
		if not assignment_error.is_empty():
			return _reject(assignment_error)
	var ship_instance := _resolve(progression, String(selection.shipInstanceId), "ship", String(selection.shipId), int(selection.shipVersion))
	var parser_instance := _resolve(progression, String(selection.parserInstanceId), "ore_parser", String(selection.parserId), int(selection.parserVersion))
	var master_instance := _resolve(progression, String(selection.masterWorkshopInstanceId), "workshop", "", 0)
	var slave_instance := _resolve(progression, String(selection.slaveWorkshopInstanceId), "workshop", "", 0)
	if ship_instance == null or parser_instance == null or master_instance == null or slave_instance == null or master_instance.instance_id == slave_instance.instance_id:
		return _reject("ship, parser, and two distinct workshop owned instances are required")
	var combination := bundle.workshop_combination_catalog.resolve_definition(String(selection.workshopId), int(selection.workshopVersion))
	if combination == null:
		return _reject("exact workshop combination definition is missing")
	var master_definition := bundle.workshop_catalog.resolve_definition(String(master_instance.definition_id), master_instance.definition_version)
	var slave_definition := bundle.workshop_catalog.resolve_definition(String(slave_instance.definition_id), slave_instance.definition_version)
	if master_definition == null or slave_definition == null:
		return _reject("both selected workshop instances must resolve to definitions in the selected component roster")
	var used_instance_ids := {
		String(ship_instance.instance_id): true,
		String(parser_instance.instance_id): true,
		String(master_instance.instance_id): true,
		String(slave_instance.instance_id): true
	}
	var base_devices: Array = []
	for raw in selection.deviceSelections:
		if not (raw is Dictionary):
			return _reject("device selection must be a dictionary")
		var instance := _resolve(progression, String(raw.get("instanceId", "")), "production_device", String(raw.get("definitionId", "")), int(raw.get("definitionVersion", 0)))
		if instance == null or used_instance_ids.has(String(instance.instance_id)):
			return _reject("production device selection is not an owned unique exact-version instance")
		used_instance_ids[String(instance.instance_id)] = true
		base_devices.append({
			"slotId": String(raw.get("slotId", "")),
			"definitionId": String(raw.get("definitionId", "")),
			"definitionVersion": int(raw.get("definitionVersion", 0))
		})
	var skill_selections: Array = []
	var skill_instances := {}
	for raw_skill in selection.skillSelections:
		if not (raw_skill is Dictionary):
			return _reject("skill selection must be a dictionary")
		var instance := _resolve(progression, String(raw_skill.get("instanceId", "")), "skill", String(raw_skill.get("skillId", "")), int(raw_skill.get("definitionVersion", 0)))
		if instance == null or used_instance_ids.has(String(instance.instance_id)):
			return _reject("selected skill is not an owned unique exact-version instance")
		used_instance_ids[String(instance.instance_id)] = true
		var order_key := String(raw_skill.get("orderDefinitionKey", ""))
		if skill_instances.has(order_key):
			return _reject("duplicate skill order key")
		skill_instances[order_key] = instance
		skill_selections.append({
			"orderDefinitionKey": order_key,
			"skillId": String(raw_skill.get("skillId", "")),
			"definitionVersion": int(raw_skill.get("definitionVersion", 0)),
			"controlArea": String(raw_skill.get("controlArea", ""))
		})
	var snapshot := SpaceHangarLoadoutAssembler.assemble(
		identity, bundle.ship_catalog, String(selection.shipId), int(selection.shipVersion),
		bundle.production_device_catalog, base_devices,
		bundle.ore_parser_catalog, String(selection.parserId), int(selection.parserVersion),
		String(selection.parserSlotId), bundle.workshop_combination_catalog,
		String(selection.workshopId), int(selection.workshopVersion),
		bundle.skill_catalog, skill_selections, bundle.balance_profile,
		float(selection.expectedBattleDurationLogicalMilli), bundle.effect_catalog,
		String(master_instance.definition_id), String(slave_instance.definition_id)
	)
	if snapshot == null:
		return null
	var frozen := snapshot.to_dictionary()
	var jar_options: Dictionary = frozen.jarWorldOptions
	var shapes: Array = jar_options.get("shapes", [])
	var ship_definition := bundle.ship_catalog.resolve_definition(String(selection.shipId), int(selection.shipVersion))
	var ship_profile := SpaceProgressionRuntimeProfileComposer.compose_ship(ship_definition, ship_instance)
	if ship_profile.is_empty():
		return _reject("ship growth attributes do not satisfy the ship subsystem contract")
	frozen.shipSelection.shipResourceProfile = ship_profile.shipResourceProfile
	frozen.shipSelection.ownedInstance = ship_instance.build_frozen_snapshot()
	var devices: Array = frozen.productionDeviceSelections
	for index in range(devices.size()):
		var device := devices[index]
		if String(device.get("deviceKind", "")) == "ore_parser":
			var parser_definition := bundle.ore_parser_catalog.resolve_definition(String(selection.parserId), int(selection.parserVersion))
			var parser_profile := SpaceProgressionRuntimeProfileComposer.compose_parser(parser_definition, parser_instance, shapes)
			if parser_profile.is_empty():
				return _reject("parser growth attributes do not satisfy parser subsystem contract")
			devices[index].oreParserProfile = parser_profile
			devices[index].ownedInstance = parser_instance.build_frozen_snapshot()
			devices[index].definitionId = String(parser_instance.definition_id)
			devices[index].definitionVersion = parser_instance.definition_version
		else:
			var matching_instance: SpaceOwnedProgressionInstance
			for raw in selection.deviceSelections:
				if String(raw.get("slotId", "")) == String(device.get("slotId", "")):
					matching_instance = progression.resolve_instance(String(raw.get("instanceId", "")))
					break
			var definition := bundle.production_device_catalog.resolve_definition(String(device.get("definitionId", "")), int(device.get("definitionVersion", 0)))
			var composed := SpaceProgressionRuntimeProfileComposer.compose_device(definition, matching_instance, String(device.get("slotId", "")))
			if composed.is_empty():
				return _reject("production device growth attributes do not satisfy its subsystem contract")
			devices[index] = composed
	frozen.productionDeviceSelections = devices
	var workshops: Array = jar_options.get("workshops", [])
	if workshops.size() != 2:
		return _reject("materialized World V2 workspace must contain exactly the two selected workshop positions")
	var selected_workshop_instances: Array[SpaceOwnedProgressionInstance] = [master_instance, slave_instance]
	var selected_workshop_definitions: Array[SpaceWorkshopDefinition] = [master_definition, slave_definition]
	for index in range(2):
		var workshop_instance := selected_workshop_instances[index]
		var workshop_definition := selected_workshop_definitions[index]
		var composed_workshop := SpaceProgressionRuntimeProfileComposer.compose_workshop(workshop_definition, workshop_instance, shapes)
		if composed_workshop.is_empty():
			return _reject("workshop growth attributes do not satisfy local workshop rules")
		var core_workshop: Dictionary = composed_workshop.duplicate(true)
		core_workshop["name"] = workshop_definition.display_name + ("（主台）" if index == 0 else "（从台）")
		workshops[index] = core_workshop
	jar_options.workshops = workshops
	frozen.jarWorldOptions = jar_options
	var workshop_selection: Dictionary = frozen.workshopCombinationSelection
	workshop_selection.masterWorkshopDefinitionId = String(master_instance.definition_id)
	workshop_selection.masterWorkshopDefinitionVersion = master_instance.definition_version
	workshop_selection.slaveWorkshopDefinitionId = String(slave_instance.definition_id)
	workshop_selection.slaveWorkshopDefinitionVersion = slave_instance.definition_version
	workshop_selection.masterWorkshopInstance = master_instance.build_frozen_snapshot()
	workshop_selection.slaveWorkshopInstance = slave_instance.build_frozen_snapshot()
	frozen.workshopCombinationSelection = workshop_selection
	for index in range(frozen.selectedOrderBindings.size()):
		var binding: Dictionary = frozen.selectedOrderBindings[index]
		var order_key := String(binding.get("orderDefinitionKey", ""))
		var skill_instance: SpaceOwnedProgressionInstance = skill_instances.get(order_key, null)
		var skill_definition := bundle.skill_catalog.resolve_skill(String(binding.get("skillDefinitionId", "")), int(binding.get("skillDefinitionVersion", 0)))
		var composed_binding := SpaceProgressionRuntimeProfileComposer.compose_skill_binding(
			binding, skill_definition, skill_instance, bundle.balance_profile, jar_options
		)
		if composed_binding.is_empty():
			return _reject("skill growth attributes do not satisfy effect parameters and benefit-to-Jar balance contracts")
		composed_binding.ownedInstance = skill_instance.build_frozen_snapshot()
		frozen.selectedOrderBindings[index] = composed_binding
	if not board_assignment_snapshot.is_empty():
		frozen["boardAssignmentSnapshot"] = board_assignment_snapshot.duplicate(true)
	frozen["progressionOwnerPlayerId"] = String(progression.player_id)
	frozen["progressionStateRevision"] = progression.state_revision
	var owned_snapshots: Array[Dictionary] = [
		ship_instance.build_frozen_snapshot(),
		master_instance.build_frozen_snapshot(), slave_instance.build_frozen_snapshot()
	]
	for device in devices:
		owned_snapshots.append(device.get("ownedInstance", {}).duplicate(true))
	for binding in frozen.selectedOrderBindings:
		owned_snapshots.append(binding.get("ownedInstance", {}).duplicate(true))
	frozen["ownedInstanceSnapshots"] = owned_snapshots
	frozen.erase("loadoutFingerprint")
	return SpaceBattleLoadoutSnapshot.create(frozen)


static func _validate_board_assignment_snapshot(snapshot: Dictionary, progression: SpacePlayerProgressionState, selection: Dictionary) -> String:
	if int(snapshot.get("schemaVersion", 0)) != 1 or String(snapshot.get("assignmentFingerprint", "")).is_empty():
		return "Board Assignment snapshot schema or fingerprint is missing"
	var board: Dictionary = snapshot.get("boardDefinition", {})
	var slots: Variant = board.get("slots", [])
	var assignments: Variant = snapshot.get("assignments", [])
	if String(board.get("boardId", "")) != String(snapshot.get("boardId", "")) or int(board.get("definitionVersion", 0)) != int(snapshot.get("definitionVersion", 0)) or not (slots is Array) or not (assignments is Array):
		return "Board Assignment snapshot does not contain its exact Board Definition"
	var slot_index := {}
	for slot in slots:
		if not (slot is Dictionary):
			return "Board Definition snapshot contains an invalid slot"
		var slot_id := String(slot.get("slotId", ""))
		if slot_id.is_empty() or slot_index.has(slot_id):
			return "Board Definition snapshot contains an empty or duplicate slot identity"
		slot_index[slot_id] = slot
	var expected_instances := {
		String(selection.get("parserInstanceId", "")): true,
		String(selection.get("masterWorkshopInstanceId", "")): true,
		String(selection.get("slaveWorkshopInstanceId", "")): true
	}
	for raw_device in selection.get("deviceSelections", []):
		if raw_device is Dictionary:
			expected_instances[String(raw_device.get("instanceId", ""))] = true
	for raw_skill in selection.get("skillSelections", []):
		if raw_skill is Dictionary:
			expected_instances[String(raw_skill.get("instanceId", ""))] = true
	var seen_slots := {}
	var seen_instances := {}
	for entry in assignments:
		if not (entry is Dictionary):
			return "Board Assignment snapshot contains an invalid assignment entry"
		var slot_id := String(entry.get("slotId", ""))
		var instance_id := String(entry.get("ownedInstanceId", ""))
		if not slot_index.has(slot_id) or seen_slots.has(slot_id) or instance_id.is_empty() or seen_instances.has(instance_id):
			return "Board Assignment snapshot contains an unknown slot or duplicated identity"
		seen_slots[slot_id] = true
		seen_instances[instance_id] = true
		var slot: Dictionary = slot_index[slot_id]
		if String(entry.get("componentKind", "")) != String(slot.get("componentKind", "")):
			return "Board Assignment component kind does not match its slot"
		var instance := progression.resolve_instance(instance_id)
		if instance == null or instance.item_kind != String(slot.get("componentKind", "")):
			return "Board Assignment references an unowned or incompatible component instance"
		if String(instance.definition_id) != String(entry.get("definitionId", "")) or instance.definition_version != int(entry.get("definitionVersion", 0)):
			return "Board Assignment exact Definition identity/version differs from the owned instance"
	for slot_id in slot_index:
		var slot: Dictionary = slot_index[slot_id]
		if bool(slot.get("required", false)) and not seen_slots.has(slot_id):
			return "Required Board Slot is empty: " + slot_id
	if assignments.size() != expected_instances.size():
		return "Board Assignment map and current runtime projection contain different component counts"
	for instance_id in expected_instances:
		if instance_id.is_empty() or not seen_instances.has(instance_id):
			return "Board Assignment map differs from selected runtime instance identities"
	return ""

static func _resolve(state: SpacePlayerProgressionState, instance_id: String, kind: String, definition_id: String, version: int) -> SpaceOwnedProgressionInstance:
	var instance := state.resolve_instance(instance_id)
	if instance == null or instance.item_kind != kind:
		return null
	if not definition_id.is_empty() and (String(instance.definition_id) != definition_id or instance.definition_version != version):
		return null
	return instance

static func _reject(reason: String) -> SpaceBattleLoadoutSnapshot:
	push_error("Owned Hangar loadout rejected: " + reason)
	return null
