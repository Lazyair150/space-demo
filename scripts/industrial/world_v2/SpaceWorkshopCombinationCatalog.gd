extends Resource
class_name SpaceWorkshopCombinationCatalog
## Exact-version workshop combination registry with detached authoring/runtime snapshots.

@export var definitions: Array[SpaceWorkshopCombinationDefinition] = []
var _definitions: Dictionary = {}

func rebuild_index() -> bool:
	_definitions.clear()
	for definition in definitions:
		if not _register_snapshot(definition):
			_definitions.clear()
			return false
	return true

func register_definition(definition: SpaceWorkshopCombinationDefinition) -> bool:
	if _definitions.is_empty() and not definitions.is_empty() and not rebuild_index():
		return false
	if not _register_snapshot(definition):
		return false
	definitions.append(_copy_definition(definition))
	return true

func _register_snapshot(definition: SpaceWorkshopCombinationDefinition) -> bool:
	if definition == null or not definition.get_validation_errors().is_empty():
		return false
	var key := _key(String(definition.combination_id), definition.definition_version)
	if _definitions.has(key):
		push_error("Duplicate workshop combination definition version: " + key)
		return false
	_definitions[key] = _copy_definition(definition)
	return true

func resolve_definition(combination_id: String, version: int) -> SpaceWorkshopCombinationDefinition:
	if _definitions.is_empty() and not definitions.is_empty() and not rebuild_index():
		return null
	var found := _definitions.get(_key(combination_id, version), null) as SpaceWorkshopCombinationDefinition
	return _copy_definition(found) if found != null else null

func create_selection(combination_id: String, version: int) -> Dictionary:
	var definition := resolve_definition(combination_id, version)
	return definition.build_selection() if definition != null else {}

func create_jar_world_options(combination_id: String, version: int) -> Dictionary:
	var definition := resolve_definition(combination_id, version)
	return definition.jar_world_options.duplicate(true) if definition != null else {}

func create_balance_profile(combination_id: String, version: int) -> Dictionary:
	var definition := resolve_definition(combination_id, version)
	if definition == null:
		return {}
	return {
		"operationCostByOrderType": definition.operation_cost_by_order_type.duplicate(true),
		"liquidHandlingOperationCost": definition.liquid_handling_operation_cost
	}

func _copy_definition(source: SpaceWorkshopCombinationDefinition) -> SpaceWorkshopCombinationDefinition:
	var copy := SpaceWorkshopCombinationDefinition.new()
	if source == null:
		return copy
	copy.combination_id = source.combination_id
	copy.definition_version = source.definition_version
	copy.display_name = source.display_name
	copy.jar_world_options = source.jar_world_options.duplicate(true)
	copy.operation_cost_by_order_type = source.operation_cost_by_order_type.duplicate(true)
	copy.liquid_handling_operation_cost = source.liquid_handling_operation_cost
	return copy

func _key(combination_id: String, version: int) -> String:
	return "%s@%d" % [combination_id, version]
