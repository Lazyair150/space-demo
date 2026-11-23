extends RefCounted
class_name SpaceHangarBoardDefinitionProbe
## Verifies the authored prototype board's slot semantics and uniqueness gate.

const DEMO_BOARD: SpaceHangarBoardDefinition = preload("res://data/hangar/demo_board.tres")

static func run() -> bool:
	if DEMO_BOARD == null or not DEMO_BOARD.get_validation_errors().is_empty():
		return false
	var config := DEMO_BOARD.build_hangar_configuration()
	if String(config.get("parserSlotId", "")) != "decomposition.parser.primary":
		return false
	if String(config.get("masterWorkshopSlotId", "")) != "workshop.master":
		return false
	if String(config.get("slaveWorkshopSlotId", "")) != "workshop.slave":
		return false
	var orders: Array = config.get("skillOrderBindings", [])
	if orders.size() != 1:
		return false
	if String(orders[0].get("orderDefinitionKey", "")) != "orders.active.primary" or String(orders[0].get("controlArea", "")) != "Active" or bool(orders[0].get("required", true)):
		return false
	var invalid := DEMO_BOARD.duplicate(true) as SpaceHangarBoardDefinition
	invalid.slots.append(invalid.slots[0].duplicate(true) as SpaceHangarBoardSlotDefinition)
	return not invalid.get_validation_errors().is_empty()
