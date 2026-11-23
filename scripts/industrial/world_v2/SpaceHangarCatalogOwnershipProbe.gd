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
		"liquids": ["blocked-liquid", "other-liquid"],
		"producers": [{"name": "probe", "rates": {"round": 1.0, "square": 0.0}}],
		"initialLiquidStock": {"blocked-liquid": 3, "other-liquid": 0},
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
	skill.jar_requirements = [{"shape": "square", "count": 2}, {"shape": "round", "count": 1}]
	skill.effect_definition_id = &"probe.effect"
	skill.ability_category = "Support"
	skill.primary_shape = &"square"
	var ability_shapes := SpaceAbilityShapeProfile.new()
	ability_shapes.profile_id = &"probe.ability-shapes"
	ability_shapes.profile_version = 1
	ability_shapes.shape_by_ability_category = {
		"Offense": "round", "Defense": "diamond", "Support": "square",
		"Reconnaissance": "triangle", "Utility": "hex"
	}
	if not ability_shapes.is_valid() or not ability_shapes.validate_skill(skill).is_empty():
		return false
	if ability_shapes.validate_shape_vocabulary(["round", "square", "diamond", "triangle", "hex"]).size() != 0:
		return false
	if ability_shapes.validate_shape_vocabulary(["round", "square"]).is_empty():
		return false
	var wrong_category_shape := skill.duplicate(true) as SpaceSkillDefinition
	wrong_category_shape.primary_shape = &"round"
	if ability_shapes.validate_skill(wrong_category_shape).is_empty():
		return false
	var no_majority_shape := skill.duplicate(true) as SpaceSkillDefinition
	no_majority_shape.jar_requirements = [{"shape": "square", "count": 1}, {"shape": "round", "count": 1}]
	if ability_shapes.validate_skill(no_majority_shape).is_empty():
		return false
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
	empty_authored_bundle.ability_shape_profile = ability_shapes
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

	# Player progression is separate from immutable catalog definitions.
	var progression := SpacePlayerProgressionState.new()
	progression.player_id = &"probe.player"
	var parser_instance := SpaceOwnedProgressionInstance.new()
	parser_instance.instance_id = &"probe.parser.instance.a"
	parser_instance.item_kind = "ore_parser"
	parser_instance.definition_id = &"probe.parser"
	parser_instance.definition_version = 1
	if progression.acquire_instance(parser_instance):
		return false # An instance cannot be acquired before its exact definition is unlocked.
	if not progression.unlock_definition("ore_parser", "probe.parser", 1):
		return false
	if progression.unlock_definition("ore_parser", "probe.parser", 1):
		return false
	if not progression.acquire_instance(parser_instance):
		return false
	var second_parser_instance := parser_instance.duplicate(true) as SpaceOwnedProgressionInstance
	second_parser_instance.instance_id = &"probe.parser.instance.b"
	if not progression.acquire_instance(second_parser_instance):
		return false
	var stale_parser_copy := progression.resolve_instance("probe.parser.instance.a")
	var upgraded_parser := progression.resolve_instance("probe.parser.instance.a")
	if upgraded_parser == null or stale_parser_copy == null:
		return false
	if not upgraded_parser.apply_progression(250, 2, {"shapeProcessingRateMultiplier": 1.25}):
		return false
	if not progression.replace_instance_progression(upgraded_parser):
		return false
	var frozen_parser := progression.build_owned_instance_snapshot("probe.parser.instance.a")
	if int(frozen_parser.get("level", 0)) != 2 or int(frozen_parser.get("progressionRevision", 0)) != 2:
		return false
	if float(frozen_parser.growthAttributes.get("shapeProcessingRateMultiplier", 0.0)) != 1.25:
		return false
	var untouched_parser := progression.resolve_instance("probe.parser.instance.b")
	if untouched_parser == null or untouched_parser.level != 1 or not untouched_parser.growth_attributes.is_empty():
		return false # Two copies of one definition progress independently.
	upgraded_parser.growth_attributes.shapeProcessingRateMultiplier = 9.0
	if float(progression.build_owned_instance_snapshot("probe.parser.instance.a").growthAttributes.shapeProcessingRateMultiplier) != 1.25:
		return false # Resolved instances and frozen snapshots are detached copies.
	if progression.replace_instance_progression(stale_parser_copy):
		return false # Progression revisions prevent stale overwrites.
	if not progression.get_validation_errors().is_empty():
		return false
	var progression_data := progression.to_data()
	if progression_data.ownedInstances.size() != 2 or progression_data.unlockedDefinitionKeys.size() != 1:
		return false
	var restored_progression := SpacePlayerProgressionState.from_data(progression_data)
	if restored_progression == null or not restored_progression.get_validation_errors().is_empty():
		return false
	if int(restored_progression.build_owned_instance_snapshot("probe.parser.instance.a").get("level", 0)) != 2:
		return false
	var invalid_progression_data := progression_data.duplicate(true)
	invalid_progression_data.ownedInstances[0].instanceId = "probe.parser.instance.a"
	if SpacePlayerProgressionState.from_data(invalid_progression_data) != null:
		return false

	# Versioned curves drive progression; the generic evaluator does not assign
	# gameplay meaning to subsystem-owned attribute keys.
	var parser_curve := SpaceProgressionCurveDefinition.new()
	parser_curve.curve_id = &"probe.parser-growth"
	parser_curve.definition_version = 2
	parser_curve.item_kind = "ore_parser"
	parser_curve.max_level = 3
	parser_curve.experience_threshold_by_level = {"2": 100, "3": 300}
	parser_curve.attribute_keyframes = {
		"shapeProcessingRateMultiplier": [
			{"level": 1, "value": 1.0},
			{"level": 2, "value": 1.25},
			{"level": 3, "value": 1.6}
		],
		"progressPerJarMultiplier": [
			{"level": 1, "value": 0.0},
			{"level": 3, "value": 4.0}
		]
	}
	if not parser_curve.get_validation_errors().is_empty():
		return false
	var curve_catalog := SpaceProgressionCurveCatalog.new()
	if not curve_catalog.register_definition(parser_curve) or curve_catalog.register_definition(parser_curve):
		return false
	var resolved_curve := curve_catalog.resolve_definition("ore_parser", "probe.parser-growth", 2)
	if resolved_curve == null or not curve_catalog.contains_definition("ore_parser", "probe.parser-growth", 2):
		return false
	resolved_curve.attribute_keyframes.shapeProcessingRateMultiplier[1].value = 99.0
	if absf(float(curve_catalog.resolve_definition("ore_parser", "probe.parser-growth", 2).attribute_keyframes.shapeProcessingRateMultiplier[1].value) - 1.25) > 0.000001:
		return false # Curve catalog returns detached immutable-by-interface copies.
	if parser_curve.level_for_experience(99) != 1 or parser_curve.level_for_experience(100) != 2 or parser_curve.level_for_experience(300) != 3:
		return false
	var level_two_growth := parser_curve.build_growth_attributes(2)
	if absf(float(level_two_growth.shapeProcessingRateMultiplier) - 1.25) > 0.000001:
		return false
	if absf(float(level_two_growth.progressPerJarMultiplier) - 2.0) > 0.000001:
		return false # Linear interpolation between authored keyframes.
	if not SpaceProgressionGrowthService.apply_with_catalog(progression, "probe.parser.instance.b", curve_catalog, "ore_parser", "probe.parser-growth", 2, 260):
		return false
	var curve_upgraded := progression.resolve_instance("probe.parser.instance.b")
	if curve_upgraded == null or curve_upgraded.level != 2 or curve_upgraded.experience != 260:
		return false
	if SpaceProgressionGrowthService.apply_with_catalog(progression, "probe.parser.instance.b", curve_catalog, "ore_parser", "probe.parser-growth", 2, 260):
		return false # Reapplying an unchanged XP total must not increment progression revision.
	if absf(float(curve_upgraded.growth_attributes.shapeProcessingRateMultiplier) - 1.25) > 0.000001:
		return false
	if curve_upgraded.growth_curve_id != parser_curve.curve_id or curve_upgraded.growth_curve_version != parser_curve.definition_version:
		return false # The exact curve version is persisted with the calculated result.
	var curve_restored_state := SpacePlayerProgressionState.from_data(progression.to_data())
	if curve_restored_state == null:
		return false
	var restored_curve_snapshot := curve_restored_state.build_owned_instance_snapshot("probe.parser.instance.b")
	if String(restored_curve_snapshot.get("growthCurveId", "")) != "probe.parser-growth" or int(restored_curve_snapshot.get("growthCurveVersion", 0)) != 2:
		return false
	var wrong_kind_curve := parser_curve.duplicate(true) as SpaceProgressionCurveDefinition
	wrong_kind_curve.item_kind = "ship"
	if SpaceProgressionGrowthService.calculate_update(curve_upgraded, wrong_kind_curve, 300) != null:
		return false # A parser curve cannot be applied to a ship instance.
	var changed_curve_version := parser_curve.duplicate(true) as SpaceProgressionCurveDefinition
	changed_curve_version.definition_version = 3
	if SpaceProgressionGrowthService.calculate_update(curve_upgraded, changed_curve_version, 300) != null:
		return false # Existing growth provenance cannot be silently switched to a new curve version.
	var regressing_xp := SpaceProgressionGrowthService.calculate_update(curve_upgraded, parser_curve, 200)
	if regressing_xp != null:
		return false
	var invalid_curve := parser_curve.duplicate(true) as SpaceProgressionCurveDefinition
	invalid_curve.experience_threshold_by_level["3"] = 90
	if invalid_curve.get_validation_errors().is_empty():
		return false # Cumulative XP thresholds must strictly increase.

	# Each subsystem interprets only its own growth attribute contract.
	var ship_growth_instance := SpaceOwnedProgressionInstance.new()
	ship_growth_instance.instance_id = &"probe.ship.growth"
	ship_growth_instance.item_kind = "ship"
	ship_growth_instance.definition_id = ship.ship_id
	ship_growth_instance.definition_version = ship.definition_version
	ship_growth_instance.growth_attributes = {"stoneProgressRateMultiplier": 1.5}
	var composed_ship := SpaceProgressionRuntimeProfileComposer.compose_ship(ships.resolve_definition("probe.ship", 2), ship_growth_instance)
	if composed_ship.is_empty() or absf(float(composed_ship.shipResourceProfile.expectedStoneProgressPerSecondByShape.round) - 3.0) > 0.000001:
		return false

	var composed_parser := SpaceProgressionRuntimeProfileComposer.compose_parser(
		parsers.resolve_definition("probe.parser", 1), curve_upgraded, ["round"]
	)
	if composed_parser.is_empty() or absf(float(composed_parser.shapeProcessingRatePerSecond.round) - 1.25) > 0.000001:
		return false
	if absf(float(composed_parser.progressPerJarByShape.round) - 2.0) > 0.000001:
		return false

	var workshop_growth_instance := SpaceOwnedProgressionInstance.new()
	workshop_growth_instance.instance_id = &"probe.workshop.growth"
	workshop_growth_instance.item_kind = "workshop"
	workshop_growth_instance.definition_id = local_master.workshop_id
	workshop_growth_instance.definition_version = local_master.definition_version
	workshop_growth_instance.growth_attributes = {"maxJarsBonus": 2, "additionalMark.square": 1}
	var composed_workshop := SpaceProgressionRuntimeProfileComposer.compose_workshop(local_master, workshop_growth_instance, ["round", "square"])
	if composed_workshop.is_empty() or int(composed_workshop.maxJars) != 10 or not composed_workshop.additionalMarks.has("square"):
		return false
	if not composed_workshop.ban.has("blocked-liquid") or int(composed_workshop.maxLiquids) != 5:
		return false

	var device_growth_instance := SpaceOwnedProgressionInstance.new()
	device_growth_instance.instance_id = &"probe.device.growth"
	device_growth_instance.item_kind = "production_device"
	device_growth_instance.definition_id = device.device_id
	device_growth_instance.definition_version = device.definition_version
	device_growth_instance.growth_attributes = {"runtimeMul.throughput": 1.5}
	var device_for_growth := device.duplicate(true) as SpaceProductionDeviceDefinition
	device_for_growth.runtime_profile = {"throughput": 2.0}
	var composed_device := SpaceProgressionRuntimeProfileComposer.compose_device(device_for_growth, device_growth_instance, "slot-growth")
	if composed_device.is_empty() or absf(float(composed_device.deviceRuntimeProfile.throughput) - 3.0) > 0.000001:
		return false

	var skill_for_growth := skill.duplicate(true) as SpaceSkillDefinition
	skill_for_growth.effect_parameters = {"damage": 10.0}
	var skill_growth_instance := SpaceOwnedProgressionInstance.new()
	skill_growth_instance.instance_id = &"probe.skill.growth"
	skill_growth_instance.item_kind = "skill"
	skill_growth_instance.definition_id = skill.skill_id
	skill_growth_instance.definition_version = skill.definition_version
	skill_growth_instance.growth_attributes = {"effectMul.damage": 1.2, "benefitMul.power": 1.2}
	var composed_skill := SpaceProgressionRuntimeProfileComposer.compose_skill(skill_for_growth, skill_growth_instance)
	if composed_skill == null or absf(float(composed_skill.effect_parameters.damage) - 12.0) > 0.000001:
		return false
	var skill_binding := {
		"benefitProfile": {"power": 10.0},
		"jarOrder": {"type": "A", "area": "Active", "cooldownDurationLogicalMilli": 10000, "requirements": [{"shape": "square"}]},
		"balanceContext": {"valid": true, "expectedBattleDurationLogicalMilli": 60000.0},
		"effectBinding": {"effectParameters": {"damage": 10.0}}
	}
	var balanced_skill_binding := SpaceProgressionRuntimeProfileComposer.compose_skill_binding(
		skill_binding, skill_for_growth, skill_growth_instance, SpaceSkillBalanceProfile.new()
	)
	if balanced_skill_binding.is_empty() or absf(float(balanced_skill_binding.benefitProfile.power) - 12.0) > 0.000001:
		return false
	if not bool(balanced_skill_binding.balanceReport.get("valid", false)):
		return false # Skill growth must be re-evaluated against the benefit-to-Jar curve.
	var cross_subsystem_growth := skill_growth_instance.duplicate(true) as SpaceOwnedProgressionInstance
	cross_subsystem_growth.growth_attributes = {"maxJarsBonus": 2}
	if SpaceProgressionRuntimeProfileComposer.compose_skill(skill_for_growth, cross_subsystem_growth) != null:
		return false
	return true
