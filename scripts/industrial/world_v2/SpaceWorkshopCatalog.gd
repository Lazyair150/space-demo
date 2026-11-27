extends Resource
class_name SpaceWorkshopCatalog
## Global exact-version catalog of independently owned workshop components.
## World profiles do not own or pre-pair these definitions; the player installs instances into board positions.

@export var definitions: Array[SpaceWorkshopDefinition] = []
var _definitions: Dictionary = {}

func rebuild_index() -> bool:
	_definitions.clear()
	for definition in definitions:
		if not _register_snapshot(definition):
			_definitions.clear()
			return false
	return true

func register_definition(definition: SpaceWorkshopDefinition) -> bool:
	if _definitions.is_empty() and not definitions.is_empty() and not rebuild_index():
		return false
	if not _register_snapshot(definition):
		return false
	definitions.append(definition.duplicate(true) as SpaceWorkshopDefinition)
	return true

func resolve_definition(definition_id: String, version: int) -> SpaceWorkshopDefinition:
	if _definitions.is_empty() and not definitions.is_empty() and not rebuild_index():
		return null
	var key := _key(definition_id, version)
	var found := _definitions.get(key, null) as SpaceWorkshopDefinition
	return found.duplicate(true) as SpaceWorkshopDefinition if found != null else null

func is_valid() -> bool:
	if definitions.is_empty():
		return false
	var candidate := SpaceWorkshopCatalog.new()
	candidate.definitions = definitions.duplicate(true)
	return candidate.rebuild_index()

func _register_snapshot(definition: SpaceWorkshopDefinition) -> bool:
	if definition == null or not definition.get_validation_errors().is_empty():
		return false
	var key := _key(String(definition.workshop_id), definition.definition_version)
	if _definitions.has(key):
		push_error("Duplicate workshop definition version: " + key)
		return false
	_definitions[key] = definition.duplicate(true) as SpaceWorkshopDefinition
	return true

func _key(definition_id: String, version: int) -> String:
	return definition_id + "@" + str(version)
