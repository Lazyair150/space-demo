extends Resource
class_name SpaceOreParserCatalog
## Exact-version registry for pre-battle universal ore-parser device definitions.
## The catalog never invents production percentages, rates, thresholds, or balance data.

## Editor-authored exact-version parser definitions. No production values are supplied by this catalog.
@export var definitions: Array[SpaceOreParserDefinition] = []

var _definitions: Dictionary = {}

func register_definition(definition: SpaceOreParserDefinition) -> bool:
	if not _register_definition_snapshot(definition):
		return false
	definitions.append(SpaceOreParserDefinition.from_runtime_profile(definition.build_runtime_profile()))
	return true

## Rebuild after loading/editing the exported definitions array in a .tres Resource.
## The runtime index always contains detached snapshots, never mutable authoring Resources.
func rebuild_index() -> bool:
	_definitions.clear()
	for definition in definitions:
		if not _register_definition_snapshot(definition):
			_definitions.clear()
			return false
	return true

func _register_definition_snapshot(definition: SpaceOreParserDefinition) -> bool:
	if definition == null:
		return false
	var key := _key(String(definition.parser_id), definition.definition_version)
	if definition.parser_id == &"" or definition.definition_version <= 0:
		push_error("Ore parser catalog rejected an unidentified definition")
		return false
	var candidate_shapes: Array = definition.shape_processing_rate_per_second.keys()
	var validation_errors := definition.get_validation_errors(candidate_shapes)
	if not validation_errors.is_empty():
		push_error("Ore parser catalog rejected an invalid universal parser definition: " + "; ".join(validation_errors))
		return false
	if _definitions.has(key):
		push_error("Duplicate ore parser definition version: " + key)
		return false
	_definitions[key] = SpaceOreParserDefinition.from_runtime_profile(definition.build_runtime_profile())
	return true

func resolve_definition(parser_id: String, version: int) -> SpaceOreParserDefinition:
	if _definitions.is_empty() and not definitions.is_empty() and not rebuild_index():
		return null
	if parser_id.strip_edges().is_empty() or version <= 0:
		return null
	var definition := _definitions.get(_key(parser_id, version), null) as SpaceOreParserDefinition
	if definition == null:
		return null
	return SpaceOreParserDefinition.from_runtime_profile(definition.build_runtime_profile())

func create_device_selection(
	parser_id: String,
	version: int,
	slot_id: String,
	shape_names: Array
) -> Dictionary:
	var definition := resolve_definition(parser_id, version)
	if definition == null:
		return {}
	return definition.build_device_selection(slot_id, shape_names)

func validate_device_selection(selection: Dictionary, expected_slot_id: String, shape_names: Array) -> Array[String]:
	var errors: Array[String] = []
	if String(selection.get("slotId", "")) != expected_slot_id or expected_slot_id.strip_edges().is_empty():
		errors.append("ore parser selection does not match its production-device slot")
	if String(selection.get("deviceKind", "")) != "ore_parser":
		errors.append("selected production device is not the universal ore parser")
	var parser_id := String(selection.get("definitionId", ""))
	var version := int(selection.get("definitionVersion", 0))
	var definition := resolve_definition(parser_id, version)
	if definition == null:
		errors.append("selected ore parser exact definition version is not present in the catalog")
		return errors
	var embedded: Variant = selection.get("oreParserProfile", null)
	if not (embedded is Dictionary):
		errors.append("selected ore parser is missing its frozen runtime profile")
	elif embedded != definition.build_runtime_profile():
		errors.append("selected ore parser profile differs from the registered exact version")
	var profile_errors := definition.get_validation_errors(shape_names)
	for error in profile_errors:
		errors.append(error)
	return errors

func registered_versions(parser_id: String) -> PackedInt32Array:
	if _definitions.is_empty() and not definitions.is_empty() and not rebuild_index():
		return PackedInt32Array()
	var versions := PackedInt32Array()
	for key in _definitions:
		var definition := _definitions[key] as SpaceOreParserDefinition
		if String(definition.parser_id) == parser_id:
			versions.append(definition.definition_version)
	versions.sort()
	return versions

func _key(parser_id: String, version: int) -> String:
	return "%s@%d" % [parser_id, version]
