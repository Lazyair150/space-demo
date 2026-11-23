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
	var ship_instance := _resolve(progression, String(selection.shipInstanceId), "ship", String(selection.shipId), int(selection.shipVersion))
	var parser_instance := _resolve(progression, String(selection.parserInstanceId), "ore_parser", String(selection.parserId), int(selection.parserVersion))
	var master_instance := _resolve(progression, String(selection.masterWorkshopInstanceId), "workshop", "", 0)
	var slave_instance := _resolve(progression, String(selection.slaveWorkshopInstanceId), "workshop", "", 0)
	if ship_instance == null or parser_instance == null or master_instance == null or slave_instance == null or master_instance.instance_id == slave_instance.instance_id:
		return _reject("ship, parser, and two distinct workshop owned instances are required")
	var combination := bundle.workshop_combination_catalog.resolve_definition(String(selection.workshopId), int(selection.workshopVersion))
	if combination == null:
		return _reject("exact workshop combination definition is missing")
	if String(master_instance.definition_id) != String(combination.workshop_pair.master_workshop_id) or String(slave_instance.definition_id) != String(combination.workshop_pair.slave_workshop_id):
		return _reject("owned workshop instances do not match the selected Master/Slave role definitions")
	var base_devices: Array = []
	for raw in selection.deviceSelections:
		if not (raw is Dictionary):
			return _reject("device selection must be a dictionary")
		var instance := _resolve(progression, String(raw.get("instanceId", "")), "production_device", String(raw.get("definitionId", "")), int(raw.get("definitionVersion", 0)))
		if instance == null:
			return _reject("production device selection is not an owned exact-version instance")
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
		if instance == null:
			return _reject("selected skill is not an owned exact-version instance")
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
		float(selection.expectedBattleDurationLogicalMilli), bundle.effect_catalog
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
	for index in range(workshops.size()):
		var authored: Dictionary = workshops[index]
		var workshop_instance := master_instance if String(authored.get("name", "")) == String(combination.workshop_definitions.filter(func(w): return w != null and String(w.workshop_id) == String(combination.workshop_pair.master_workshop_id))[0].display_name) else slave_instance
		var workshop_definition := _find_workshop(combination, String(workshop_instance.definition_id), workshop_instance.definition_version)
		var composed_workshop := SpaceProgressionRuntimeProfileComposer.compose_workshop(workshop_definition, workshop_instance, shapes)
		if composed_workshop.is_empty():
			return _reject("workshop growth attributes do not satisfy local workshop rules")
		workshops[index] = composed_workshop
	jar_options.workshops = workshops
	frozen.jarWorldOptions = jar_options
	var workshop_selection: Dictionary = frozen.workshopCombinationSelection
	workshop_selection.masterWorkshopInstance = master_instance.build_frozen_snapshot()
	workshop_selection.slaveWorkshopInstance = slave_instance.build_frozen_snapshot()
	frozen.workshopCombinationSelection = workshop_selection
	for index in range(frozen.selectedOrderBindings.size()):
		var binding: Dictionary = frozen.selectedOrderBindings[index]
		var order_key := String(binding.get("orderDefinitionKey", ""))
		var skill_instance: SpaceOwnedProgressionInstance = skill_instances.get(order_key, null)
		var skill_definition := bundle.skill_catalog.resolve_skill(String(binding.get("skillDefinitionId", "")), int(binding.get("skillDefinitionVersion", 0)))
		var composed_skill := SpaceProgressionRuntimeProfileComposer.compose_skill(skill_definition, skill_instance)
		if composed_skill == null:
			return _reject("skill growth attributes do not satisfy the skill subsystem contract")
		binding.effectBinding.effectParameters = composed_skill.effect_parameters.duplicate(true)
		binding.ownedInstance = skill_instance.build_frozen_snapshot()
		frozen.selectedOrderBindings[index] = binding
	frozen["progressionOwnerPlayerId"] = String(progression.player_id)
	frozen["progressionStateRevision"] = progression.state_revision
	var owned_snapshots: Array[Dictionary] = [
		ship_instance.build_frozen_snapshot(), parser_instance.build_frozen_snapshot(),
		master_instance.build_frozen_snapshot(), slave_instance.build_frozen_snapshot()
	]
	for device in devices:
		owned_snapshots.append(device.get("ownedInstance", {}).duplicate(true))
	for binding in frozen.selectedOrderBindings:
		owned_snapshots.append(binding.get("ownedInstance", {}).duplicate(true))
	frozen["ownedInstanceSnapshots"] = owned_snapshots
	frozen.erase("loadoutFingerprint")
	return SpaceBattleLoadoutSnapshot.create(frozen)

static func _resolve(state: SpacePlayerProgressionState, instance_id: String, kind: String, definition_id: String, version: int) -> SpaceOwnedProgressionInstance:
	var instance := state.resolve_instance(instance_id)
	if instance == null or instance.item_kind != kind:
		return null
	if not definition_id.is_empty() and (String(instance.definition_id) != definition_id or instance.definition_version != version):
		return null
	return instance

static func _find_workshop(combination: SpaceWorkshopCombinationDefinition, definition_id: String, version: int) -> SpaceWorkshopDefinition:
	for definition in combination.workshop_definitions:
		if definition != null and String(definition.workshop_id) == definition_id and definition.definition_version == version:
			return definition.duplicate(true) as SpaceWorkshopDefinition
	return null

static func _reject(reason: String) -> SpaceBattleLoadoutSnapshot:
	push_error("Owned Hangar loadout rejected: " + reason)
	return null
