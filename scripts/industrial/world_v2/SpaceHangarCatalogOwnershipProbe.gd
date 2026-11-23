extends RefCounted
class_name SpaceHangarCatalogOwnershipProbe
## Synthetic ownership checks only; contains no production balance or world configuration.

static func run() -> bool:
	var ship := SpaceShipDefinition.new()
	ship.ship_id = &"probe.ship"
	ship.definition_version = 2
	ship.display_name = "Probe Ship"
	ship.expected_stone_progress_per_second_by_shape = {"round": 2.0}
	var ships := SpaceShipCatalog.new()
	if not ships.register_definition(ship):
		return false
	ship.display_name = "Mutated Ship"
	ship.expected_stone_progress_per_second_by_shape["round"] = 99.0
	var resolved_ship := ships.resolve_definition("probe.ship", 2)
	if resolved_ship == null or resolved_ship.display_name != "Probe Ship":
		return false
	resolved_ship.expected_stone_progress_per_second_by_shape["round"] = 77.0
	if float(ships.resolve_definition("probe.ship", 2).expected_stone_progress_per_second_by_shape["round"]) != 2.0:
		return false
	if ships.resolve_definition("probe.ship", 1) != null:
		return false

	var device := SpaceProductionDeviceDefinition.new()
	device.device_id = &"probe.device"
	device.definition_version = 4
	device.device_kind = "probe_processor"
	device.display_name = "Probe Processor"
	device.runtime_profile = {"nested": {"value": 1}}
	var devices := SpaceProductionDeviceCatalog.new()
	if not devices.register_definition(device):
		return false
	device.runtime_profile.nested.value = 2
	var resolved_device := devices.resolve_definition("probe.device", 4)
	if resolved_device == null or int(resolved_device.runtime_profile.nested.value) != 1:
		return false
	resolved_device.runtime_profile.nested.value = 3
	if int(devices.resolve_definition("probe.device", 4).runtime_profile.nested.value) != 1:
		return false
	if devices.create_selection("probe.device", 4, "slot-a").is_empty():
		return false
	if devices.create_selection("probe.device", 3, "slot-a").size() != 0:
		return false

	var workshop := SpaceWorkshopCombinationDefinition.new()
	workshop.combination_id = &"probe.workshop"
	workshop.definition_version = 5
	workshop.display_name = "Probe Workshop"
	workshop.jar_world_options = {
		"shapes": ["round"],
		"liquids": [],
		"producers": [],
		"workshops": [{"name": "Probe Master"}],
		"masterWorkshopName": "Probe Master"
	}
	workshop.operation_cost_by_order_type = {"A": 1.0, "B": 2.0}
	workshop.liquid_handling_operation_cost = 0.5
	var workshops := SpaceWorkshopCombinationCatalog.new()
	if not workshops.register_definition(workshop):
		return false
	workshop.jar_world_options.shapes[0] = "mutated"
	workshop.operation_cost_by_order_type["A"] = 99.0
	var resolved_workshop := workshops.resolve_definition("probe.workshop", 5)
	if resolved_workshop == null or String(resolved_workshop.jar_world_options.shapes[0]) != "round":
		return false
	if float(resolved_workshop.operation_cost_by_order_type["A"]) != 1.0:
		return false
	resolved_workshop.jar_world_options.shapes[0] = "mutated-resolved"
	resolved_workshop.operation_cost_by_order_type["A"] = 88.0
	if String(workshops.create_jar_world_options("probe.workshop", 5).shapes[0]) != "round":
		return false
	if float(workshops.create_balance_profile("probe.workshop", 5).operationCostByOrderType["A"]) != 1.0:
		return false
	if workshops.resolve_definition("probe.workshop", 4) != null:
		return false
	return true
