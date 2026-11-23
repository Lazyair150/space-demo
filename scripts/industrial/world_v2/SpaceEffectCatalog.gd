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
	var detached := definition.duplicate(true) as BuffDefinition
	if detached == null or not detached.is_valid():
		return false
	_definitions[key] = detached
	return true

func resolve_buff(definition_id: String, version: int) -> BuffDefinition:
	if definition_id.strip_edges().is_empty() or version <= 0:
		return null
	var result: Variant = _definitions.get(_key(definition_id, version), null)
	if not (result is BuffDefinition):
		return null
	# Never expose the catalog-owned Resource; callers receive an isolated exact-version copy.
	return (result as BuffDefinition).duplicate(true) as BuffDefinition

func resolve_balance_metrics(definition_id: String, version: int) -> Dictionary:
	var definition := resolve_buff(definition_id, version)
	if definition == null or definition.balance_metrics.is_empty():
		return {}
	var metrics := definition.balance_metrics.duplicate(true)
	# These values are derived from the exact effect definition, never hand-copied into a skill.
	metrics["duration"] = definition.duration
	metrics["periodic_damage"] = float(definition.tick_damage) * floor(definition.duration / definition.tick_interval) if definition.tick_interval > 0.0 else 0.0
	metrics["stack_potential"] = float(definition.max_stacks) if definition.stack_policy == BuffDefinition.StackPolicy.ADD_STACK else 1.0
	return metrics

func contains(definition_id: String, version: int) -> bool:
	return resolve_buff(definition_id, version) != null

func _key(definition_id: String, version: int) -> String:
	return "%s@%d" % [definition_id, version]
