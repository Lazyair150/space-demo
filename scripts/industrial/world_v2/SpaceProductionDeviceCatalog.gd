extends Resource
class_name SpaceProductionDeviceCatalog
## Exact-version registry for production devices other than the mandatory universal ore parser.

@export var definitions: Array[SpaceProductionDeviceDefinition] = []
var _definitions: Dictionary = {}

func rebuild_index() -> bool:
	_definitions.clear()
	for definition in definitions:
		if not _register_snapshot(definition):
			_definitions.clear()
			return false
	return true

func register_definition(definition: SpaceProductionDeviceDefinition) -> bool:
	if _definitions.is_empty() and not definitions.is_empty() and not rebuild_index():
		return false
	if not _register_snapshot(definition):
		return false
	definitions.append(_copy_definition(definition))
	return true

func _register_snapshot(definition: SpaceProductionDeviceDefinition) -> bool:
	if definition == null or not definition.is_valid():
		return false
	var key := _key(String(definition.device_id), definition.definition_version)
	if _definitions.has(key):
		push_error("Duplicate production device definition version: " + key)
		return false
	_definitions[key] = _copy_definition(definition)
	return true

func resolve_definition(device_id: String, version: int) -> SpaceProductionDeviceDefinition:
	if _definitions.is_empty() and not definitions.is_empty() and not rebuild_index():
		return null
	var found := _definitions.get(_key(device_id, version), null) as SpaceProductionDeviceDefinition
	return _copy_definition(found) if found != null else null

func create_selection(device_id: String, version: int, slot_id: String) -> Dictionary:
	var definition := resolve_definition(device_id, version)
	return definition.build_selection(slot_id) if definition != null else {}

func _copy_definition(source: SpaceProductionDeviceDefinition) -> SpaceProductionDeviceDefinition:
	var copy := SpaceProductionDeviceDefinition.new()
	if source == null:
		return copy
	copy.device_id = source.device_id
	copy.definition_version = source.definition_version
	copy.device_kind = source.device_kind
	copy.display_name = source.display_name
	copy.display_icon = source.display_icon
	copy.runtime_profile = source.runtime_profile.duplicate(true)
	return copy

func _key(device_id: String, version: int) -> String:
	return "%s@%d" % [device_id, version]
