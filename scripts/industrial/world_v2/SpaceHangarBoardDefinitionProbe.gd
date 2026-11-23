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
	var assembled := SpaceHangarOwnedLoadoutAssembler.assemble(identity, runtime_catalog, selection, progression)
	if assembled == null:
		return false
	var frozen_data := assembled.to_dictionary()
	frozen_data["assemblyBoard"] = DEMO_BOARD.build_frozen_snapshot()
	frozen_data.erase("loadoutFingerprint")
	var frozen := SpaceBattleLoadoutSnapshot.create(frozen_data)
	if frozen == null or frozen.order_definition_keys().size() != 2:
		return false
	if frozen.to_dictionary().get("ownedInstanceSnapshots", []).size() != 6:
		return false
	var invalid := DEMO_BOARD.duplicate(true) as SpaceHangarBoardDefinition
	invalid.slots.append(invalid.slots[0].duplicate(true) as SpaceHangarBoardSlotDefinition)
	return not invalid.get_validation_errors().is_empty()
