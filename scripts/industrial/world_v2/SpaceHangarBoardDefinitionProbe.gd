extends RefCounted
class_name SpaceHangarBoardDefinitionProbe
## Verifies generic board structure separately from the narrower current runtime projection.

const DEMO_BOARD: SpaceHangarBoardDefinition = preload("res://data/hangar/demo_board.tres")

static func run() -> bool:
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
	if slot_index.size() != 4 or DEMO_BOARD.get_slots_for_area("workshop").size() != 2:
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
	if expanded_config.get("skillOrderBindings", []).size() != 2 or expanded_config.get("deviceSlotIds", []).size() != 1:
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

	var invalid := DEMO_BOARD.duplicate(true) as SpaceHangarBoardDefinition
	invalid.slots.append(invalid.slots[0].duplicate(true) as SpaceHangarBoardSlotDefinition)
	return not invalid.get_validation_errors().is_empty()
