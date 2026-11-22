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

func create_order_binding(skill_id: String, version: int, order_definition_key: String, selected_control_area: String, balance_profile: SpaceSkillBalanceProfile, balance_context: Dictionary = {}) -> Dictionary:
	var definition := resolve_skill(skill_id, version)
	if definition == null:
		return {}
	return definition.create_order_binding(order_definition_key, selected_control_area, balance_profile, balance_context)

func create_order_binding_for_build(
	skill_id: String,
	version: int,
	order_definition_key: String,
	selected_control_area: String,
	balance_profile: SpaceSkillBalanceProfile,
	production_devices: Array,
	workshop_combination: Dictionary,
	expected_battle_duration_logical_milli: float
) -> Dictionary:
	var definition := resolve_skill(skill_id, version)
	if definition == null:
		return {}
	if balance_profile == null or not balance_profile.is_valid():
		return {}
	var jar_order := definition.build_jar_order()
	if jar_order.is_empty():
		return {}
	var context := SpaceSkillBuildContextEvaluator.evaluate(
		jar_order,
		production_devices,
		workshop_combination,
		expected_battle_duration_logical_milli,
		balance_profile
	)
	if not context.get("valid", false):
		push_error("Skill build difficulty context rejected: " + String(context.get("reason", "unknown")))
		return {}
	return definition.create_order_binding(order_definition_key, selected_control_area, balance_profile, context)

func _key(skill_id: String, version: int) -> String:
	return "%s@%d" % [skill_id, version]
