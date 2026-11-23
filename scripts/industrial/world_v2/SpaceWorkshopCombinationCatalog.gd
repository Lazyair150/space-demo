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

func create_jar_world_options(combination_id: String, version: int, master_workshop_id: String = "", slave_workshop_id: String = "") -> Dictionary:
	var definition := resolve_definition(combination_id, version)
	return definition.build_jar_world_options(master_workshop_id, slave_workshop_id) if definition != null else {}

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
	copy.display_icon = source.display_icon
	copy.jar_world_options = source.jar_world_options.duplicate(true)
	copy.core_order_templates.clear()
	for template in source.core_order_templates:
		copy.core_order_templates.append(template.duplicate_definition() if template != null else null)
	copy.workshop_definitions.clear()
	for workshop in source.workshop_definitions:
		if workshop == null:
			copy.workshop_definitions.append(null)
		else:
			copy.workshop_definitions.append(workshop.duplicate(true) as SpaceWorkshopDefinition)
	if source.workshop_pair != null:
		copy.workshop_pair = source.workshop_pair.duplicate(true) as SpaceWorkshopPairDefinition
	copy.operation_cost_by_order_type = source.operation_cost_by_order_type.duplicate(true)
	copy.liquid_handling_operation_cost = source.liquid_handling_operation_cost
	return copy

func _key(combination_id: String, version: int) -> String:
	return "%s@%d" % [combination_id, version]
