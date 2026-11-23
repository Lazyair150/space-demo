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
	var frozen_data := assembled.to_dictionary()
	var frozen := SpaceBattleLoadoutSnapshot.create(frozen_data)
	if frozen == null or frozen.order_definition_keys().size() != 2:
		return false
	if frozen.to_dictionary().get("ownedInstanceSnapshots", []).size() != 6 or not frozen_data.has("boardAssignmentSnapshot"):
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
		"skillChoices": [{"id": "skill.beam", "version": 3, "instanceId": "owned.skill", "progressionRevision": 6, "itemKind": "skill"}]
	}
	var assignments := {
		"workshop.master": {
			"slotId": "workshop.master", "componentKind": "workshop",
			"ownedInstanceId": "owned.master", "definitionId": "workshop.alpha", "definitionVersion": 1, "sourceRevision": 4
		},
		"workshop.slave": {
			"slotId": "workshop.slave", "componentKind": "workshop",
			"ownedInstanceId": "owned.slave", "definitionId": "workshop.alpha", "definitionVersion": 1, "sourceRevision": 4
		},
		"decomposition.parser.primary": {
			"slotId": "decomposition.parser.primary", "componentKind": "ore_parser",
			"ownedInstanceId": "owned.parser", "definitionId": "parser.basic", "definitionVersion": 1, "sourceRevision": 2
		}
	}
	if not SpaceHangarBoardAssignment.validate(DEMO_BOARD, assignments, inventory).is_empty():
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
	return not SpaceHangarBoardAssignment.validate(DEMO_BOARD, wrong_kind, inventory).is_empty()

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
