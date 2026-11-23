extends RefCounted
class_name SpaceHangarCatalogOwnershipProbe
## Synthetic ownership checks only; contains no production balance or world configuration.

static func run() -> bool:
	var ship := SpaceShipDefinition.new()
	ship.ship_id = &"probe.ship"
	ship.definition_version = 2
	ship.display_name = "Probe Ship"
	ship.display_icon = GradientTexture2D.new()
	ship.display_hull_texture = GradientTexture2D.new()
	var ship_anchor := SpaceShipDisplayAnchor.new()
	ship_anchor.anchor_id = &"probe-anchor"
	ship_anchor.logical_slot_id = "slot-a"
	ship_anchor.component_kind = "device"
	ship_anchor.normalized_position = Vector2(0.7, 0.5)
	ship.display_anchors.append(ship_anchor)
	ship.expected_stone_progress_per_second_by_shape = {"round": 2.0}
	var ships := SpaceShipCatalog.new()
	if not ships.register_definition(ship):
		return false
	ship.display_name = "Mutated Ship"
	ship.expected_stone_progress_per_second_by_shape["round"] = 99.0
	var resolved_ship := ships.resolve_definition("probe.ship", 2)
	if resolved_ship == null or resolved_ship.display_name != "Probe Ship" or resolved_ship.display_icon == null or resolved_ship.display_hull_texture == null or resolved_ship.display_anchors.size() != 1:
		return false
	resolved_ship.expected_stone_progress_per_second_by_shape["round"] = 77.0
	if float(ships.resolve_definition("probe.ship", 2).expected_stone_progress_per_second_by_shape["round"]) != 2.0:
		return false
	if String(ships.resolve_definition("probe.ship", 2).display_anchors[0].logical_slot_id) != "slot-a":
		return false
	ship_anchor.logical_slot_id = "mutated-slot"
	if String(ships.resolve_definition("probe.ship", 2).display_anchors[0].logical_slot_id) != "slot-a":
		return false
	var invalid_display_copy := ships.resolve_definition("probe.ship", 2)
	invalid_display_copy.display_anchors[0].normalized_position = Vector2(2.0, 0.5)
	if not invalid_display_copy.get_validation_errors(["round"]).is_empty() or invalid_display_copy.get_display_validation_errors().is_empty():
		return false
	if ships.resolve_definition("probe.ship", 1) != null:
		return false

	var device := SpaceProductionDeviceDefinition.new()
	device.device_id = &"probe.device"
	device.definition_version = 4
	device.device_kind = "probe_processor"
	device.display_name = "Probe Processor"
	device.display_icon = GradientTexture2D.new()
	device.runtime_profile = {"nested": {"value": 1}}
	var devices := SpaceProductionDeviceCatalog.new()
	if not devices.register_definition(device):
		return false
	device.runtime_profile.nested.value = 2
	var resolved_device := devices.resolve_definition("probe.device", 4)
	if resolved_device == null or int(resolved_device.runtime_profile.nested.value) != 1 or resolved_device.display_icon == null:
		return false
	resolved_device.runtime_profile.nested.value = 3
	if int(devices.resolve_definition("probe.device", 4).runtime_profile.nested.value) != 1:
		return false
	if devices.create_selection("probe.device", 4, "slot-a").is_empty():
		return false
	if devices.create_selection("probe.device", 3, "slot-a").size() != 0:
		return false

	var local_master := SpaceWorkshopDefinition.new()
	local_master.workshop_id = &"probe.master"
	local_master.definition_version = 1
	local_master.display_name = "Probe Master"
	local_master.base_marks = ["round"]
	local_master.additional_marks = ["square"]
	local_master.banned_liquids = ["blocked-liquid"]
	local_master.max_jars = 8
	local_master.max_liquids = 5
	local_master.liquid_staging_capacity = 3
	var local_slave := SpaceWorkshopDefinition.new()
	local_slave.workshop_id = &"probe.slave"
	local_slave.definition_version = 2
	local_slave.display_name = "Probe Slave"
	local_slave.base_marks = ["round"]
	local_slave.max_jars = 4
	local_slave.max_liquids = 2
	var pair := SpaceWorkshopPairDefinition.new()
	pair.pair_id = &"probe.pair"
	pair.definition_version = 3
	pair.display_name = "Probe Master/Slave Pair"
	pair.master_workshop_id = local_master.workshop_id
	pair.slave_workshop_id = local_slave.workshop_id

	var workshop := SpaceWorkshopCombinationDefinition.new()
	workshop.combination_id = &"probe.workshop"
	workshop.definition_version = 5
	workshop.display_name = "Probe Workshop"
	workshop.display_icon = GradientTexture2D.new()
	workshop.jar_world_options = {
		"shapes": ["round", "square"],
		"liquids": ["blocked-liquid"],
		"producers": [{"name": "probe", "rates": {"round": 1.0}}],
		"initialLiquidStock": {"blocked-liquid": 3},
		"jarFlowRatePerLogicalTime": 1.0,
		"liquidFlowRatePerLogicalTime": 1.0,
		"executionLogicalTimePerUnit": 1000
	}
	workshop.workshop_definitions = [local_master, local_slave]
	workshop.workshop_pair = pair
	workshop.operation_cost_by_order_type = {"A": 1.0, "B": 2.0}
	workshop.liquid_handling_operation_cost = 0.5
	var workshops := SpaceWorkshopCombinationCatalog.new()
	if not workshops.register_definition(workshop):
		return false
	local_master.base_marks[0] = "mutated"
	local_master.banned_liquids[0] = "mutated"
	pair.master_workshop_id = &"probe.slave"
	workshop.jar_world_options.shapes[0] = "mutated"
	workshop.operation_cost_by_order_type["A"] = 99.0
	var resolved_workshop := workshops.resolve_definition("probe.workshop", 5)
	if resolved_workshop == null or String(resolved_workshop.jar_world_options.shapes[0]) != "round" or resolved_workshop.display_icon == null:
		return false
	if float(resolved_workshop.operation_cost_by_order_type["A"]) != 1.0:
		return false
	var resolved_options := workshops.create_jar_world_options("probe.workshop", 5)
	if String(resolved_options.workshops[0].baseMarks[0]) != "round" or String(resolved_options.workshops[0].ban[0]) != "blocked-liquid":
		return false
	if String(resolved_options.masterWorkshopName) != "Probe Master" or String(resolved_options.slaveWorkshopName) != "Probe Slave":
		return false
	if int(resolved_options.workshops[0].maxLiquids) != 5 or int(resolved_options.workshops[0].liquidStagingCapacity) != 3:
		return false
	if not workshops.create_selection("probe.workshop", 5).has("workshopPair"):
		return false
	resolved_workshop.jar_world_options.shapes[0] = "mutated-resolved"
	resolved_workshop.operation_cost_by_order_type["A"] = 88.0
	if String(workshops.create_jar_world_options("probe.workshop", 5).shapes[0]) != "round":
		return false
	if float(workshops.create_balance_profile("probe.workshop", 5).operationCostByOrderType["A"]) != 1.0:
		return false
	if workshops.resolve_definition("probe.workshop", 4) != null:
		return false

	var parser := SpaceOreParserDefinition.new()
	parser.parser_id = &"probe.parser"
	parser.definition_version = 1
	parser.display_name = "Probe Parser"
	parser.display_icon = GradientTexture2D.new()
	parser.production_percentage = 100
	parser.shape_processing_rate_per_second = {"round": 1.0}
	parser.progress_per_jar_by_shape = {"round": 1.0}
	var parsers := SpaceOreParserCatalog.new()
	if not parsers.register_definition(parser):
		return false
	var resolved_parser := parsers.resolve_definition("probe.parser", 1)
	if resolved_parser == null or resolved_parser.display_name != "Probe Parser" or resolved_parser.display_icon == null:
		return false

	var skill := SpaceSkillDefinition.new()
	skill.skill_id = &"probe.visual-skill"
	skill.definition_version = 1
	skill.display_name = "Probe Visual Skill"
	skill.display_icon = GradientTexture2D.new()
	skill.jar_requirements = [{"shape": "round", "count": 1}]
	skill.effect_definition_id = &"probe.effect"
	skill.ability_category = "Support"
	var skills := SpaceSkillCatalog.new()
	if not skills.register_skill(skill) or skills.resolve_skill("probe.visual-skill", 1).display_icon == null or skills.resolve_skill("probe.visual-skill", 1).ability_category != "Support":
		return false

	var effect := BuffDefinition.new()
	effect.id = &"probe.effect"
	effect.definition_version = 1
	effect.label = "Probe Effect"
	effect.display_icon = GradientTexture2D.new()
	var effects := SpaceEffectCatalog.new()
	if not effects.register_buff(effect) or effects.resolve_buff("probe.effect", 1).display_icon == null:
		return false

	var valid_selection := SpaceHangarSelection.from_data({
		"shipId": "probe.ship", "shipVersion": 2,
		"deviceSelections": [{"slotId": "slot-a", "definitionId": "probe.device", "definitionVersion": 4}],
		"parserId": "probe.parser", "parserVersion": 1, "parserSlotId": "parser-slot",
		"workshopId": "probe.workshop", "workshopVersion": 5,
		"skillSelections": [{"skillId": "probe.skill", "definitionVersion": 3, "orderDefinitionKey": "probe.order", "controlArea": "primary"}],
		"expectedBattleDurationLogicalMilli": 60000.0
	})
	if not valid_selection.validate().is_empty():
		return false
	var detached_data := valid_selection.to_data()
	detached_data.deviceSelections[0].slotId = "mutated"
	if String(valid_selection.to_data().deviceSelections[0].slotId) != "slot-a":
		return false
	var duplicate_selection := SpaceHangarSelection.from_data({
		"shipId": "probe.ship", "shipVersion": 2,
		"deviceSelections": [
			{"slotId": "same", "definitionId": "probe.a", "definitionVersion": 1},
			{"slotId": "same", "definitionId": "probe.b", "definitionVersion": 1}
		],
		"parserId": "probe.parser", "parserVersion": 1, "parserSlotId": "same",
		"workshopId": "probe.workshop", "workshopVersion": 5,
		"skillSelections": [
			{"skillId": "probe.skill", "definitionVersion": 3, "orderDefinitionKey": "duplicate", "controlArea": "primary"},
			{"skillId": "probe.skill", "definitionVersion": 3, "orderDefinitionKey": "duplicate", "controlArea": "secondary"}
		],
		"expectedBattleDurationLogicalMilli": 60000.0
	})
	if duplicate_selection.validate().is_empty():
		return false
	var incomplete_bundle := SpaceHangarCatalogBundle.create(
		SpaceShipCatalog.new(), SpaceProductionDeviceCatalog.new(),
		SpaceOreParserCatalog.new(), SpaceWorkshopCombinationCatalog.new(),
		null, null, null
	)
	if incomplete_bundle.validate_and_prepare().is_empty():
		return false
	var empty_authored_bundle := SpaceHangarCatalogBundleResource.new()
	empty_authored_bundle.ship_catalog = SpaceShipCatalog.new()
	empty_authored_bundle.production_device_catalog = SpaceProductionDeviceCatalog.new()
	empty_authored_bundle.ore_parser_catalog = SpaceOreParserCatalog.new()
	empty_authored_bundle.workshop_combination_catalog = SpaceWorkshopCombinationCatalog.new()
	empty_authored_bundle.balance_profile = SpaceSkillBalanceProfile.new()
	if empty_authored_bundle.create_runtime_bundle() != null:
		return false
	var empty_inventory := empty_authored_bundle.build_selection_inventory()
	if bool(empty_inventory.get("isReady", true)) or not empty_inventory.get("shipChoices", []).is_empty():
		return false
	var draft := SpaceHangarSelectionDraft.new()
	var draft_inventory := {
		"isReady": true,
		"shipChoices": [{"id": "probe.ship", "version": 2}],
		"deviceChoices": [{"id": "probe.device", "version": 4}],
		"parserChoices": [{"id": "probe.parser", "version": 1}],
		"workshopChoices": [{"id": "probe.workshop", "version": 5}],
		"skillChoices": [{"id": "probe.skill", "version": 3, "allowedControlAreas": ["primary"]}]
	}
	if not draft.configure(draft_inventory):
		return false
	if draft.set_ship("probe.ship", 1) or not draft.set_ship("probe.ship", 2):
		return false
	if not draft.set_parser("probe.parser", 1, "parser-slot"):
		return false
	if draft.set_device("parser-slot", "probe.device", 4):
		return false
	if not draft.set_device("device-slot", "probe.device", 4):
		return false
	if draft.set_skill("probe.order", "probe.skill", 3, "secondary"):
		return false
	if not draft.set_skill("probe.order", "probe.skill", 3, "primary"):
		return false
	if not draft.set_workshop("probe.workshop", 5) or not draft.set_expected_battle_duration(60000.0):
		return false
	var drafted_selection := draft.build_selection()
	if drafted_selection == null or not drafted_selection.validate().is_empty():
		return false
	var unavailable_draft := SpaceHangarSelectionDraft.new()
	if unavailable_draft.configure({"isReady": false}) or unavailable_draft.set_ship("probe.ship", 2):
		return false
	var unconfigured_preparation := SpaceHangarPreparation.new()
	var selection_controller := SpaceHangarSelectionController.new()
	if selection_controller.configure(unconfigured_preparation, {"shipWorldId": "probe.world", "loadoutId": "probe.loadout", "loadoutVersion": 1}):
		return false
	var unavailable_view := selection_controller.get_view_model()
	if bool(unavailable_view.get("isReady", true)) or bool(unavailable_view.get("canBuild", true)):
		return false
	if not unavailable_view.get("inventory", {}).get("shipChoices", []).is_empty():
		return false
	return true
