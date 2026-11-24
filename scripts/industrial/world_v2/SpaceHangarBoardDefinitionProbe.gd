extends RefCounted
class_name SpaceHangarBoardDefinitionProbe
## Verifies generic board structure separately from the narrower current runtime projection.

const DEMO_BOARD: SpaceHangarBoardDefinition = preload("res://data/hangar/demo_board.tres")
const DEMO_CATALOG: SpaceHangarCatalogBundleResource = preload("res://data/hangar/demo_catalog_bundle.tres")

static func run() -> bool:
	if DEMO_CATALOG == null:
		return false
	var runtime_catalog := DEMO_CATALOG.create_runtime_bundle()
	if runtime_catalog == null or runtime_catalog.workshop_catalog == null or runtime_catalog.workshop_catalog.resolve_definition("demo.workshop.alpha", 1) == null:
		return false
	if runtime_catalog.workshop_combination_catalog.resolve_definition("demo.world.starter", 1) == null or runtime_catalog.workshop_combination_catalog.resolve_definition("demo.world.deep_field", 1) == null:
		return false
	if not DEMO_CATALOG.workshop_combination_catalog.definitions[0].workshop_definitions.is_empty():
		return false
	var runtime_world := runtime_catalog.workshop_combination_catalog.resolve_definition("demo.world.starter", 1)
	if runtime_world.workshop_definitions.size() != 2:
		return false
	if runtime_catalog.skill_catalog == null or runtime_catalog.skill_catalog.is_empty() or runtime_catalog.effect_catalog == null or runtime_catalog.effect_catalog.is_empty():
		return false
	if runtime_catalog.ore_parser_catalog.resolve_definition("demo.parser.universal", 1) == null or runtime_catalog.ore_parser_catalog.resolve_definition("demo.parser.precision", 1) == null:
		return false
	if DEMO_BOARD == null or not DEMO_BOARD.get_validation_errors().is_empty():
		return false
	if not DEMO_BOARD.get_runtime_projection_errors().is_empty():
		return false
	var frozen_board := DEMO_BOARD.build_frozen_snapshot()
	if String(frozen_board.get("boardId", "")) != "demo.circuit_board" or frozen_board.get("slots", []).size() != 5:
		return false
	var config := DEMO_BOARD.build_hangar_configuration()
	if String(config.get("parserSlotId", "")) != "decomposition.parser.primary":
		return false
	if String(config.get("masterWorkshopSlotId", "")) != "workshop.master":
		return false
	if String(config.get("slaveWorkshopSlotId", "")) != "workshop.slave":
		return false
	var orders: Array = config.get("skillOrderBindings", [])
	if orders.size() != 2:
		return false
	var order_areas := {}
	for order in orders:
		order_areas[String(order.get("orderDefinitionKey", ""))] = String(order.get("controlArea", ""))
	if order_areas.get("orders.active.primary", "") != "Active" or order_areas.get("orders.passive.recon", "") != "Passive":
		return false
	var slot_index := DEMO_BOARD.build_slot_index()
	if slot_index.size() != 5 or DEMO_BOARD.get_slots_for_area("workshop").size() != 2:
		return false

	# The board structure accepts multiple independent positions in the same area.
	# Current runtime projection supports multiple order/device slots, but not multiple parsers.
	var expanded := DEMO_BOARD.duplicate(true) as SpaceHangarBoardDefinition
	var second_order := expanded.resolve_slot("orders.active.primary")
	second_order.slot_id = &"orders.passive.secondary"
	second_order.display_name = "被动订单槽位"
	second_order.control_area = "Passive"
	expanded.slots.append(second_order)
	var second_device := SpaceHangarBoardSlotDefinition.new()
	second_device.slot_id = &"production.secondary"
	second_device.area_id = "production"
	second_device.component_kind = "production_device"
	second_device.display_name = "第二生产元件"
	expanded.slots.append(second_device)
	if not expanded.get_validation_errors().is_empty() or not expanded.get_runtime_projection_errors().is_empty():
		return false
	var expanded_config := expanded.build_hangar_configuration()
	if expanded_config.get("skillOrderBindings", []).size() != 3 or expanded_config.get("deviceSlotIds", []).size() != 1:
		return false

	# Unsupported multiplicity is rejected explicitly, never silently overwritten.
	var multi_parser := expanded.duplicate(true) as SpaceHangarBoardDefinition
	var extra_parser := SpaceHangarBoardSlotDefinition.new()
	extra_parser.slot_id = &"decomposition.parser.secondary"
	extra_parser.area_id = "decomposition"
	extra_parser.component_kind = "ore_parser"
	extra_parser.display_name = "第二分解器"
	multi_parser.slots.append(extra_parser)
	if not multi_parser.get_validation_errors().is_empty():
		return false
	if multi_parser.get_runtime_projection_errors().is_empty() or not multi_parser.build_hangar_configuration().is_empty():
		return false

	# End-to-end prototype inventory -> owned-instance assembly -> frozen board snapshot.
	var progression := SpaceDemoProgressionBootstrap.create_starting_inventory(DEMO_CATALOG)
	if progression == null:
		return false
	var inventory := SpaceHangarOwnedInventoryBuilder.build(DEMO_CATALOG, progression)
	if not bool(inventory.get("isReady", false)):
		return false
	if inventory.parserChoices.size() != 2 or inventory.workshopInstanceChoices.size() != 2 or inventory.skillChoices.size() != 2 or inventory.workshopWorldChoices.size() != 2:
		return false
	# Exercise the same generic Owned Instance -> Board Slot assignment path used by Hangar UI.
	var generic_draft := SpaceHangarSelectionDraft.new()
	if not generic_draft.configure(inventory, DEMO_BOARD):
		return false
	if not generic_draft.set_ship("demo.ship.starter", 1, "demo.ship.starter.01"):
		return false
	if not generic_draft.set_workshop("demo.world.starter", 1):
		return false
	var generic_assignments := {
		"workshop.master": "demo.workshop.alpha.01",
		"workshop.slave": "demo.workshop.beta.01",
		"decomposition.parser.primary": "demo.parser.precision.01",
		"orders.active.primary": "demo.skill.rapid_fire.01",
		"orders.passive.recon": "demo.skill.recon_scan.01"
	}
	for slot_id in generic_assignments:
		if not generic_draft.assign_instance(slot_id, String(generic_assignments[slot_id])):
			return false
	if not generic_draft.validate_assignments().is_empty():
		return false
	var generic_selection := generic_draft.build_selection()
	if generic_selection == null:
		return false
	var generic_assignment_snapshot := generic_draft.build_assignment_snapshot()
	if generic_assignment_snapshot.is_empty() or generic_assignment_snapshot.get("assignments", []).size() != 5:
		return false
	var identity := {
		"shipWorldId": "demo.ship_world",
		"loadoutId": "demo.starter.loadout",
		"loadoutVersion": 1
	}
	var selection := {
		"shipId": "demo.ship.starter", "shipVersion": 1, "shipInstanceId": "demo.ship.starter.01",
		"parserId": "demo.parser.precision", "parserVersion": 1, "parserSlotId": "decomposition.parser.primary",
		"parserInstanceId": "demo.parser.precision.01",
		"workshopId": "demo.world.starter", "workshopVersion": 1,
		"masterWorkshopInstanceId": "demo.workshop.alpha.01",
		"slaveWorkshopInstanceId": "demo.workshop.beta.01",
		"deviceSelections": [],
		"skillSelections": [
			{"orderDefinitionKey": "orders.active.primary", "skillId": "demo.skill.rapid_fire", "definitionVersion": 1, "controlArea": "Active", "instanceId": "demo.skill.rapid_fire.01"},
			{"orderDefinitionKey": "orders.passive.recon", "skillId": "demo.skill.recon_scan", "definitionVersion": 1, "controlArea": "Passive", "instanceId": "demo.skill.recon_scan.01"}
		],
		"expectedBattleDurationLogicalMilli": 60000.0
	}
	selection["boardAssignments"] = SpaceHangarBoardAssignment.build_from_selection(DEMO_BOARD, selection, inventory)
	if selection.boardAssignments.is_empty():
		return false
	var assembled := SpaceHangarOwnedLoadoutAssembler.assemble(identity, runtime_catalog, selection, progression)
	if assembled == null:
		return false
	# A Parser contribution must not leak into the Core workshop Rule Profile.
	var parser_definition := runtime_catalog.ore_parser_catalog.resolve_definition("demo.parser.precision", 1)
	if parser_definition == null:
		return false
	var original_parser_rules: Array = parser_definition.rule_contributions.duplicate()
	var unsupported_parser_rule := SpaceRuleContributionDefinition.new()
	unsupported_parser_rule.rule_id = &"probe.parser.local-rule"
	unsupported_parser_rule.rule_version = 1
	unsupported_parser_rule.effect = "ModifyIntensity"
	unsupported_parser_rule.target = "parser.throughput"
	unsupported_parser_rule.scope = "parser"
	parser_definition.rule_contributions = [unsupported_parser_rule]
	var core_profile := SpaceRuleContributionResolver.resolve(generic_assignment_snapshot, runtime_catalog, progression)
	parser_definition.rule_contributions = original_parser_rules
	if core_profile.is_empty():
		return false
	var parser_slot_id := ""
	for assignment in generic_assignment_snapshot.get("assignments", []):
		if assignment is Dictionary and String(assignment.get("componentKind", "")) == "ore_parser":
			parser_slot_id = String(assignment.get("slotId", ""))
			break
	if parser_slot_id.is_empty():
		return false
	for contribution in core_profile.get("contributions", []):
		var source: Dictionary = contribution.get("source", {})
		if String(source.get("slotId", "")) == parser_slot_id or String(contribution.get("scope", "")) != "workshop":
			return false

	# The owned assembler must route a supported Parser rule to Space's Parser profile
	# while keeping the Core-facing workshop profile free of that Parser contribution.
	var parser_rule_shape := String(assembled.to_dictionary().get("jarWorldOptions", {}).get("shapes", [])[0])
	var supported_parser_rule := SpaceRuleContributionDefinition.new()
	supported_parser_rule.rule_id = &"probe.parser.owned-rate-rule"
	supported_parser_rule.rule_version = 1
	supported_parser_rule.effect = "ModifyIntensity"
	supported_parser_rule.target = "shape_processing_rate"
	supported_parser_rule.scope = "parser"
	supported_parser_rule.parameters = {"shape": parser_rule_shape, "multiplier": 1.25}
	parser_definition.rule_contributions = [supported_parser_rule]
	var parser_rule_assembled := SpaceHangarOwnedLoadoutAssembler.assemble(identity, runtime_catalog, selection, progression)
	parser_definition.rule_contributions = original_parser_rules
	if parser_rule_assembled == null:
		return false
	var parser_rule_loadout := parser_rule_assembled.to_dictionary()
	var parser_rule_device: Dictionary = {}
	for device in parser_rule_loadout.get("productionDeviceSelections", []):
		if device is Dictionary and String(device.get("deviceKind", "")) == "ore_parser":
			parser_rule_device = device
			break
	if parser_rule_device.is_empty() or not parser_rule_device.get("oreParserProfile", {}).has("parserRuleProfile"):
		return false
	for contribution in parser_rule_loadout.get("boardRuleProfile", {}).get("contributions", []):
		var source: Dictionary = contribution.get("source", {})
		if String(source.get("slotId", "")) == parser_slot_id:
			return false

	var frozen_data := assembled.to_dictionary()
	var frozen := SpaceBattleLoadoutSnapshot.create(frozen_data)
	if frozen == null or frozen.order_definition_keys().size() != 2:
		return false
	if frozen.to_dictionary().get("ownedInstanceSnapshots", []).size() != 6 or not frozen_data.has("boardAssignmentSnapshot"):
		return false
	var runtime_profile_set: Dictionary = frozen_data.get("boardRuntimeProfileSet", {})
	if runtime_profile_set.get("entries", []).size() != 5:
		return false
	var routed_consumers := {}
	for route in runtime_profile_set.get("entries", []):
		var consumer := String(route.get("consumer", ""))
		routed_consumers[consumer] = int(routed_consumers.get(consumer, 0)) + 1
	if int(routed_consumers.get("jar_core.workshop", 0)) != 2 or int(routed_consumers.get("space.parser", 0)) != 1 or int(routed_consumers.get("space.skill", 0)) != 2:
		return false

	# A route must bind to the exact installed Owned Instance and Definition revision,
	# not merely to a profile that happens to occupy the same slot.
	var wrong_parser_identity := frozen_data.duplicate(true)
	wrong_parser_identity.productionDeviceSelections[0].definitionId = "parser.other"
	if not SpaceBoardRuntimeProfileSet.build(
		wrong_parser_identity.boardAssignmentSnapshot,
		wrong_parser_identity.jarWorldOptions,
		wrong_parser_identity.productionDeviceSelections,
		wrong_parser_identity.selectedOrderBindings,
		wrong_parser_identity.workshopCombinationSelection
	).is_empty():
		return false
	var wrong_parser_instance := frozen_data.duplicate(true)
	wrong_parser_instance.productionDeviceSelections[0].oreParserProfile.ownedInstance.instanceId = "parser.foreign.copy"
	if not SpaceBoardRuntimeProfileSet.build(
		wrong_parser_instance.boardAssignmentSnapshot,
		wrong_parser_instance.jarWorldOptions,
		wrong_parser_instance.productionDeviceSelections,
		wrong_parser_instance.selectedOrderBindings,
		wrong_parser_instance.workshopCombinationSelection
	).is_empty():
		return false
	var wrong_skill_provenance := frozen_data.duplicate(true)
	wrong_skill_provenance.selectedOrderBindings[0].ownedInstance.progressionRevision += 1
	if not SpaceBoardRuntimeProfileSet.build(
		wrong_skill_provenance.boardAssignmentSnapshot,
		wrong_skill_provenance.jarWorldOptions,
		wrong_skill_provenance.productionDeviceSelections,
		wrong_skill_provenance.selectedOrderBindings,
		wrong_skill_provenance.workshopCombinationSelection
	).is_empty():
		return false
	var wrong_workshop_provenance := frozen_data.duplicate(true)
	wrong_workshop_provenance.workshopCombinationSelection.masterWorkshopInstance.definitionVersion += 1
	if not SpaceBoardRuntimeProfileSet.build(
		wrong_workshop_provenance.boardAssignmentSnapshot,
		wrong_workshop_provenance.jarWorldOptions,
		wrong_workshop_provenance.productionDeviceSelections,
		wrong_workshop_provenance.selectedOrderBindings,
		wrong_workshop_provenance.workshopCombinationSelection
	).is_empty():
		return false

	var duplicate_parser_profile := frozen_data.duplicate(true)
	duplicate_parser_profile.productionDeviceSelections.append(duplicate_parser_profile.productionDeviceSelections[0].duplicate(true))
	if not SpaceBoardRuntimeProfileSet.build(
		duplicate_parser_profile.boardAssignmentSnapshot,
		duplicate_parser_profile.jarWorldOptions,
		duplicate_parser_profile.productionDeviceSelections,
		duplicate_parser_profile.selectedOrderBindings,
		duplicate_parser_profile.workshopCombinationSelection
	).is_empty():
		return false
	var duplicate_skill_binding := frozen_data.duplicate(true)
	duplicate_skill_binding.selectedOrderBindings.append(duplicate_skill_binding.selectedOrderBindings[0].duplicate(true))
	if not SpaceBoardRuntimeProfileSet.build(
		duplicate_skill_binding.boardAssignmentSnapshot,
		duplicate_skill_binding.jarWorldOptions,
		duplicate_skill_binding.productionDeviceSelections,
		duplicate_skill_binding.selectedOrderBindings,
		duplicate_skill_binding.workshopCombinationSelection
	).is_empty():
		return false

	var tampered_profile_set := frozen_data.duplicate(true)
	tampered_profile_set.boardRuntimeProfileSet.entries[0].profileFingerprint = "invalid"
	if SpaceBattleLoadoutSnapshot.create(tampered_profile_set) != null:
		return false
	if not _probe_assignments() or not _probe_rule_contributions():
		return false

	var invalid := DEMO_BOARD.duplicate(true) as SpaceHangarBoardDefinition
	invalid.slots.append(invalid.slots[0].duplicate(true) as SpaceHangarBoardSlotDefinition)
	return not invalid.get_validation_errors().is_empty()

static func _probe_assignments() -> bool:
	var inventory := {
		"isReady": true,
		"parserChoices": [{"id": "parser.basic", "version": 1, "instanceId": "owned.parser", "progressionRevision": 2, "itemKind": "ore_parser"}],
		"deviceChoices": [{"id": "device.fabricator", "version": 2, "instanceId": "owned.device", "progressionRevision": 3, "itemKind": "production_device"}],
		"workshopInstanceChoices": [
			{"id": "workshop.alpha", "version": 1, "instanceId": "owned.master", "progressionRevision": 4, "itemKind": "workshop"},
			{"id": "workshop.alpha", "version": 1, "instanceId": "owned.slave", "progressionRevision": 5, "itemKind": "workshop"}
		],
		"skillChoices": [{"id": "skill.beam", "version": 3, "instanceId": "owned.skill", "progressionRevision": 6, "itemKind": "skill", "allowedControlAreas": ["Active", "Passive"]}]
	}
	var assignments := {
		"workshop.master": {
			"slotId": "workshop.master", "componentKind": "workshop", "roleId": "master",
			"ownedInstanceId": "owned.master", "definitionId": "workshop.alpha", "definitionVersion": 1, "sourceRevision": 4
		},
		"workshop.slave": {
			"slotId": "workshop.slave", "componentKind": "workshop", "roleId": "slave",
			"ownedInstanceId": "owned.slave", "definitionId": "workshop.alpha", "definitionVersion": 1, "sourceRevision": 5
		},
		"decomposition.parser.primary": {
			"slotId": "decomposition.parser.primary", "componentKind": "ore_parser",
			"ownedInstanceId": "owned.parser", "definitionId": "parser.basic", "definitionVersion": 1, "sourceRevision": 2
		}
	}
	if not SpaceHangarBoardAssignment.validate(DEMO_BOARD, assignments, inventory).is_empty():
		return false
	var active_skill_slot := DEMO_BOARD.resolve_slot("orders.active.primary")
	var skill_entry := SpaceHangarBoardAssignment.create_entry(active_skill_slot, inventory.skillChoices[0])
	if String(skill_entry.get("controlArea", "")) != "Active":
		return false
	var first_snapshot := SpaceHangarBoardAssignment.build_snapshot(DEMO_BOARD, assignments)
	var reversed := {}
	var keys: Array = assignments.keys()
	keys.reverse()
	for key in keys:
		reversed[key] = assignments[key]
	var second_snapshot := SpaceHangarBoardAssignment.build_snapshot(DEMO_BOARD, reversed)
	if String(first_snapshot.get("assignmentFingerprint", "")) != String(second_snapshot.get("assignmentFingerprint", "")):
		return false
	var duplicate_instance := assignments.duplicate(true)
	duplicate_instance["orders.active.primary"] = {
		"slotId": "orders.active.primary", "componentKind": "skill",
		"ownedInstanceId": "owned.parser", "definitionId": "parser.basic", "definitionVersion": 1
	}
	if SpaceHangarBoardAssignment.validate(DEMO_BOARD, duplicate_instance, inventory).is_empty():
		return false
	var wrong_kind := assignments.duplicate(true)
	wrong_kind["decomposition.parser.primary"]["componentKind"] = "workshop"
	if SpaceHangarBoardAssignment.validate(DEMO_BOARD, wrong_kind, inventory).is_empty():
		return false

	# Changing a World profile that excludes installed workshop instances must be rejected,
	# not silently converted into empty Master/Slave slots.
	var compatibility_inventory := {
		"isReady": true,
		"workshopWorldChoices": [
			{"id": "world.compatible", "version": 1},
			{"id": "world.incompatible", "version": 1}
		],
		"workshopInstanceChoices": [
			{"id": "workshop.alpha", "version": 1, "instanceId": "owned.compat.master", "progressionRevision": 1, "itemKind": "workshop", "compatibleWorldKeys": ["world.compatible@1"]},
			{"id": "workshop.beta", "version": 1, "instanceId": "owned.compat.slave", "progressionRevision": 1, "itemKind": "workshop", "compatibleWorldKeys": ["world.compatible@1"]}
		]
	}
	var compatibility_draft := SpaceHangarSelectionDraft.new()
	if not compatibility_draft.configure(compatibility_inventory, DEMO_BOARD):
		return false
	if not compatibility_draft.set_workshop("world.compatible", 1):
		return false
	if not compatibility_draft.assign_instance("workshop.master", "owned.compat.master"):
		return false
	if not compatibility_draft.assign_instance("workshop.slave", "owned.compat.slave"):
		return false
	if compatibility_draft.set_workshop("world.incompatible", 1, "owned.compat.master", "owned.compat.slave"):
		return false
	return (
		String(compatibility_draft.get_assignment("workshop.master").get("ownedInstanceId", "")) == "owned.compat.master"
		and String(compatibility_draft.get_assignment("workshop.slave").get("ownedInstanceId", "")) == "owned.compat.slave"
	)

static func _probe_rule_contributions() -> bool:
	var definition := SpaceRuleContributionDefinition.new()
	definition.rule_id = &"component.output-modifier"
	definition.rule_version = 2
	definition.effect = "ModifyIntensity"
	definition.target = "liquid:蜜"
	definition.scope = "workshop"
	definition.priority = 4
	definition.parameters = {"factorPerMille": 1000}
	definition.growth_parameter_bindings = {"factorPerMille": "outputFactor"}
	if not definition.get_validation_errors().is_empty():
		return false
	var instance := SpaceOwnedProgressionInstance.new()
	instance.instance_id = &"owned.rule-probe"
	instance.item_kind = "workshop"
	instance.definition_id = &"workshop.alpha"
	instance.definition_version = 3
	instance.progression_revision = 7
	instance.growth_attributes = {"outputFactor": 1450}
	var resolved := definition.resolve(instance, "workshop.master")
	if resolved.is_empty():
		return false
	var source: Dictionary = resolved.get("source", {})
	var parameters: Dictionary = resolved.get("parameters", {})
	if String(source.get("sourceInstanceId", "")) != "owned.rule-probe" or int(source.get("sourceRevision", 0)) != 7:
		return false
	if String(source.get("slotId", "")) != "workshop.master" or String(parameters.get("factorPerMille", "")) != "1450":
		return false
	instance.growth_attributes.clear()
	return definition.resolve(instance, "workshop.master").is_empty()
