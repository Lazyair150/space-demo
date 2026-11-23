extends Resource
class_name SpaceShipCatalog
## Exact-version ship registry. Registered and resolved definitions are detached snapshots.

@export var definitions: Array[SpaceShipDefinition] = []
var _definitions: Dictionary = {}

func rebuild_index() -> bool:
	_definitions.clear()
	for definition in definitions:
		if not _register_snapshot(definition):
			_definitions.clear()
			return false
	return true

func register_definition(definition: SpaceShipDefinition) -> bool:
	if _definitions.is_empty() and not definitions.is_empty() and not rebuild_index():
		return false
	if not _register_snapshot(definition):
		return false
	definitions.append(_copy_definition(definition))
	return true

func _register_snapshot(definition: SpaceShipDefinition) -> bool:
	if definition == null:
		return false
	var key := _key(String(definition.ship_id), definition.definition_version)
	if definition.ship_id == &"" or definition.definition_version <= 0 or _definitions.has(key):
		push_error("Ship catalog rejected invalid or duplicate exact-version identity: " + key)
		return false
	var copy := _copy_definition(definition)
	_definitions[key] = copy
	return true

func resolve_definition(ship_id: String, version: int) -> SpaceShipDefinition:
	if _definitions.is_empty() and not definitions.is_empty() and not rebuild_index():
		return null
	var found := _definitions.get(_key(ship_id, version), null) as SpaceShipDefinition
	return _copy_definition(found) if found != null else null

func create_selection(ship_id: String, version: int, configured_shapes: Array) -> Dictionary:
	var definition := resolve_definition(ship_id, version)
	if definition == null:
		return {}
	return definition.build_selection(configured_shapes)

func _copy_definition(source: SpaceShipDefinition) -> SpaceShipDefinition:
	var copy := SpaceShipDefinition.new()
	if source == null:
		return copy
	copy.ship_id = source.ship_id
	copy.definition_version = source.definition_version
	copy.display_name = source.display_name
	copy.display_icon = source.display_icon
	copy.expected_stone_progress_per_second_by_shape = source.expected_stone_progress_per_second_by_shape.duplicate(true)
	return copy

func _key(ship_id: String, version: int) -> String:
	return "%s@%d" % [ship_id, version]
