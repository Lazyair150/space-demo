extends RefCounted
class_name SpaceEffectCatalog
## Exact-version registry for Space-owned skill effects. Jar never sees these Resources.

var _definitions: Dictionary = {}

func register_buff(definition: BuffDefinition) -> bool:
	if definition == null or not definition.is_valid() or definition.definition_version <= 0:
		push_error("Space effect catalog rejected an invalid/versionless BuffDefinition")
		return false
	var key := _key(String(definition.id), definition.definition_version)
	if _definitions.has(key):
		push_error("Duplicate Space effect definition version: " + key)
		return false
	_definitions[key] = definition
	return true

func resolve_buff(definition_id: String, version: int) -> BuffDefinition:
	if definition_id.strip_edges().is_empty() or version <= 0:
		return null
	var result: Variant = _definitions.get(_key(definition_id, version), null)
	return result as BuffDefinition

func resolve_balance_metrics(definition_id: String, version: int) -> Dictionary:
	var definition := resolve_buff(definition_id, version)
	if definition == null or definition.balance_metrics.is_empty():
		return {}
	return definition.balance_metrics.duplicate(true)

func contains(definition_id: String, version: int) -> bool:
	return resolve_buff(definition_id, version) != null

func _key(definition_id: String, version: int) -> String:
	return "%s@%d" % [definition_id, version]
