extends RefCounted
class_name SpaceHangarLoadoutAssembler
## Domain assembler: resolves exact-version authored selections and emits one frozen loadout.
## This class does not invent catalog values, compatibility rules, or balance assumptions.

static func assemble(
	identity: Dictionary,
	ship_catalog: SpaceShipCatalog,
	ship_id: String,
	ship_version: int,
	device_catalog: SpaceProductionDeviceCatalog,
	device_selections: Array,
	parser_catalog: SpaceOreParserCatalog,
	parser_id: String,
	parser_version: int,
	parser_slot_id: String,
	workshop_catalog: SpaceWorkshopCombinationCatalog,
	workshop_id: String,
	workshop_version: int,
	skill_catalog: SpaceSkillCatalog,
	skill_selections: Array,
	balance_profile: SpaceSkillBalanceProfile,
	expected_battle_duration_logical_milli: float,
	effect_catalog: SpaceEffectCatalog
) -> SpaceBattleLoadoutSnapshot:
	if ship_catalog == null or device_catalog == null or parser_catalog == null:
		return _reject("required ship/device/parser catalog is missing")
	if workshop_catalog == null or skill_catalog == null or balance_profile == null or effect_catalog == null:
		return _reject("required workshop/skill/balance/effect dependency is missing")
	for key in ["shipWorldId", "loadoutId", "loadoutVersion"]:
		if not identity.has(key):
			return _reject("loadout identity is missing " + key)
	if String(identity.shipWorldId).strip_edges().is_empty() or String(identity.loadoutId).strip_edges().is_empty() or int(identity.loadoutVersion) <= 0:
		return _reject("loadout identity is invalid")

	var workshop_selection := workshop_catalog.create_selection(workshop_id, workshop_version)
	var jar_options := workshop_catalog.create_jar_world_options(workshop_id, workshop_version)
	var workshop_profile := workshop_catalog.create_balance_profile(workshop_id, workshop_version)
	if workshop_selection.is_empty() or jar_options.is_empty() or workshop_profile.is_empty():
		return _reject("selected exact workshop combination version cannot be materialized")
	var shapes_value: Variant = jar_options.get("shapes", null)
	if not (shapes_value is Array) or shapes_value.is_empty():
		return _reject("selected workshop combination has no configured Jar shapes")
	var shapes: Array = shapes_value

	var ship_selection := ship_catalog.create_selection(ship_id, ship_version, shapes)
	if ship_selection.is_empty():
		return _reject("selected exact ship version is missing or incompatible with Jar shapes")
	var ship_resource_profile: Dictionary = ship_selection.get("shipResourceProfile", {}).duplicate(true)

	var resolved_devices: Array = []
	var used_slots := {}
	for raw_choice in device_selections:
		if not (raw_choice is Dictionary):
			return _reject("production device choice must be a dictionary")
		var slot_id := String(raw_choice.get("slotId", "")).strip_edges()
		var device_id := String(raw_choice.get("definitionId", "")).strip_edges()
		var version := int(raw_choice.get("definitionVersion", 0))
		if slot_id.is_empty() or used_slots.has(slot_id) or slot_id == parser_slot_id:
			return _reject("production device slot is empty, duplicated, or collides with parser slot")
		used_slots[slot_id] = true
		var selection := device_catalog.create_selection(device_id, version, slot_id)
		if selection.is_empty():
			return _reject("selected production device exact version cannot be resolved: " + device_id)
		resolved_devices.append(selection)

	var parser_definition := parser_catalog.resolve_definition(parser_id, parser_version)
	if parser_definition == null or not parser_definition.is_valid_for_shapes(shapes):
		return _reject("selected exact universal parser version is missing or incompatible with Jar shapes")
	var parser_profile := parser_definition.build_runtime_profile()

	var selected_bindings: Array = []
	var used_order_keys := {}
	for raw_skill in skill_selections:
		if not (raw_skill is Dictionary):
			return _reject("skill selection must be a dictionary")
		var order_key := String(raw_skill.get("orderDefinitionKey", "")).strip_edges()
		if order_key.is_empty() or used_order_keys.has(order_key):
			return _reject("skill orderDefinitionKey is empty or duplicated")
		used_order_keys[order_key] = true
		var binding := skill_catalog.create_order_binding_for_build(
			String(raw_skill.get("skillId", "")),
			int(raw_skill.get("definitionVersion", 0)),
			order_key,
			String(raw_skill.get("controlArea", "")),
			balance_profile,
			resolved_devices + [parser_definition.build_device_selection(parser_slot_id, shapes)],
			workshop_profile,
			ship_resource_profile,
			parser_profile.progressPerJarByShape,
			expected_battle_duration_logical_milli,
			effect_catalog
		)
		if binding.is_empty():
			return _reject("skill could not be bound against the selected build: " + order_key)
		selected_bindings.append(binding)

	var source := {
		"schemaVersion": SpaceBattleLoadoutSnapshot.CURRENT_SCHEMA_VERSION,
		"shipWorldId": String(identity.shipWorldId),
		"loadoutId": String(identity.loadoutId),
		"loadoutVersion": int(identity.loadoutVersion),
		"shipSelection": ship_selection,
		"productionDeviceSelections": resolved_devices,
		"workshopCombinationSelection": workshop_selection,
		"jarWorldOptions": jar_options,
		"selectedOrderBindings": selected_bindings
	}
	var frozen := SpaceBattleLoadoutSnapshot.create_with_ore_parser(
		source, parser_catalog, parser_id, parser_version, parser_slot_id
	)
	if frozen == null:
		return _reject("complete loadout failed immutable snapshot validation")
	return frozen

static func _reject(reason: String) -> SpaceBattleLoadoutSnapshot:
	push_error("Hangar loadout assembly rejected: " + reason)
	return null
