extends Resource
class_name SpaceWorkshopCombinationDefinition
## Versioned workshop roster and authored cost profile. Values are design data, never defaults.

@export var combination_id: StringName = &""
@export var definition_version: int = 1
@export var display_name: String = ""
@export var jar_world_options: Dictionary = {}
@export var operation_cost_by_order_type: Dictionary = {}
@export var liquid_handling_operation_cost: float = 0.0

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if combination_id == &"" or definition_version <= 0:
		errors.append("workshop combination identity/version is invalid")
	if display_name.strip_edges().is_empty():
		errors.append("workshop combination display name is required")
	for key in ["shapes", "liquids", "producers", "workshops", "masterWorkshopName"]:
		if not jar_world_options.has(key):
			errors.append("workshop combination Jar options are missing " + key)
	var shapes: Variant = jar_world_options.get("shapes", null)
	if not (shapes is Array) or shapes.is_empty():
		errors.append("workshop combination must provide a non-empty Jar shape vocabulary")
	var workshops: Variant = jar_world_options.get("workshops", null)
	if not (workshops is Array) or workshops.is_empty():
		errors.append("workshop combination must provide a non-empty workshop roster")
	if not operation_cost_by_order_type.has("A") or not operation_cost_by_order_type.has("B"):
		errors.append("workshop combination must author operation costs for both A and B")
	for order_type in ["A", "B"]:
		var raw_cost: Variant = operation_cost_by_order_type.get(order_type, null)
		if (typeof(raw_cost) != TYPE_INT and typeof(raw_cost) != TYPE_FLOAT) or not is_finite(float(raw_cost)) or float(raw_cost) < 0.0:
			errors.append("workshop operation cost is invalid for order type " + order_type)
	if not is_finite(liquid_handling_operation_cost) or liquid_handling_operation_cost < 0.0:
		errors.append("liquid handling operation cost must be finite and non-negative")
	return errors

func build_selection() -> Dictionary:
	if not get_validation_errors().is_empty():
		return {}
	return {
		"definitionId": String(combination_id),
		"definitionVersion": definition_version,
		"workshopCombinationProfile": {
			"operationCostByOrderType": operation_cost_by_order_type.duplicate(true),
			"liquidHandlingOperationCost": liquid_handling_operation_cost
		}
	}
