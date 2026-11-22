extends RefCounted
class_name SpaceSkillCatalog
## Exact-version registry for player-facing, equipable skills.

var _definitions: Dictionary = {}

func register_skill(definition: SpaceSkillDefinition) -> bool:
	if definition == null or not definition.is_valid():
		push_error("Skill Catalog rejected an invalid skill definition")
		return false
	var key := _key(String(definition.skill_id), definition.definition_version)
	if _definitions.has(key):
		push_error("Duplicate skill definition version: " + key)
		return false
	_definitions[key] = definition
	return true

func resolve_skill(skill_id: String, version: int) -> SpaceSkillDefinition:
	if skill_id.strip_edges().is_empty() or version <= 0:
		return null
	return _definitions.get(_key(skill_id, version), null) as SpaceSkillDefinition

func create_order_binding(skill_id: String, version: int, order_definition_key: String) -> Dictionary:
	var definition := resolve_skill(skill_id, version)
	if definition == null:
		return {}
	return definition.create_order_binding(order_definition_key)

func _key(skill_id: String, version: int) -> String:
	return "%s@%d" % [skill_id, version]
