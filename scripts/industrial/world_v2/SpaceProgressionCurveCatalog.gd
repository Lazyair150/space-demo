extends RefCounted
class_name SpaceProgressionCurveCatalog
## Exact-version registry for authored progression curves.
## Callers resolve a curve once for a progression transaction and persist its identity/version.

var _definitions: Dictionary = {}

func register_definition(definition: SpaceProgressionCurveDefinition) -> bool:
	if definition == null or not definition.get_validation_errors().is_empty():
		return false
	var key := _curve_key(definition.item_kind, String(definition.curve_id), definition.definition_version)
	if _definitions.has(key):
		return false
	_definitions[key] = definition.duplicate(true)
	return true

func resolve_definition(
	item_kind: String,
	curve_id: String,
	definition_version: int
) -> SpaceProgressionCurveDefinition:
	var key := _curve_key(item_kind, curve_id, definition_version)
	if key.is_empty() or not _definitions.has(key):
		return null
	return _definitions[key].duplicate(true) as SpaceProgressionCurveDefinition

func contains_definition(item_kind: String, curve_id: String, definition_version: int) -> bool:
	return not _curve_key(item_kind, curve_id, definition_version).is_empty() and _definitions.has(
		_curve_key(item_kind, curve_id, definition_version)
	)

func definition_count() -> int:
	return _definitions.size()

static func _curve_key(item_kind: String, curve_id: String, version: int) -> String:
	if not SpaceProgressionCurveDefinition.ITEM_KINDS.has(item_kind) or curve_id.strip_edges().is_empty() or version <= 0:
		return ""
	return "%s:%s@%d" % [item_kind, curve_id, version]
