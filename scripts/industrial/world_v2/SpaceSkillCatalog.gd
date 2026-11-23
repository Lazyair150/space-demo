extends RefCounted
class_name SpaceSkillCatalog
## Exact-version registry for player-facing, equipable skills.
## Registered Resources are detached snapshots; callers never receive the catalog's instance.

var _definitions: Dictionary = {}

func register_skill(definition: SpaceSkillDefinition) -> bool:
	if definition == null or not definition.is_valid():
		push_error("Skill Catalog rejected an invalid skill definition")
		return false
	var key := _key(String(definition.skill_id), definition.definition_version)
	if _definitions.has(key):
		push_error("Duplicate skill definition version: " + key)
		return false
	_definitions[key] = definition.duplicate(true) as SpaceSkillDefinition
	return true

func resolve_skill(skill_id: String, version: int) -> SpaceSkillDefinition:
	if skill_id.strip_edges().is_empty() or version <= 0:
		return null
	var definition := _definitions.get(_key(skill_id, version), null) as SpaceSkillDefinition
	if definition == null:
		return null
	return definition.duplicate(true) as SpaceSkillDefinition

func create_order_binding_for_build(
	skill_id: String,
	version: int,
	order_definition_key: String,
	selected_control_area: String,
	balance_profile: SpaceSkillBalanceProfile,
	production_devices: Array,
	workshop_combination: Dictionary,
	ship_resource_profile: Dictionary,
	shape_progress_per_jar: Dictionary,
	expected_battle_duration_logical_milli: float,
	effect_catalog: SpaceEffectCatalog,
	jar_world_options: Dictionary = {}
) -> Dictionary:
	var definition := resolve_skill(skill_id, version)
	if definition == null:
		return {}
	if balance_profile == null or not balance_profile.is_valid() or effect_catalog == null:
		return {}
	var effect_id := String(definition.effect_definition_id)
	var benefit_metrics := effect_catalog.resolve_balance_metrics(effect_id, definition.effect_definition_version)
	if benefit_metrics.is_empty():
		push_error("Skill effect version has no balance metrics: " + effect_id)
		return {}
	var jar_order := definition.build_jar_order(selected_control_area)
	if jar_order.is_empty():
		return {}
	var balance_jar_order := jar_order.duplicate(true)
	if definition.jar_order_template_id != &"":
		balance_jar_order = resolve_order_template(definition, jar_world_options, selected_control_area)
		if balance_jar_order.is_empty():
			return {}
	var context := SpaceSkillBuildContextEvaluator.evaluate(
		balance_jar_order,
		production_devices,
		workshop_combination,
		ship_resource_profile,
		shape_progress_per_jar,
		expected_battle_duration_logical_milli,
		balance_profile
	)
	if not context.get("valid", false):
		push_error("Skill build difficulty context rejected: " + String(context.get("reason", "unknown")))
		return {}
	return definition.create_order_binding(order_definition_key, selected_control_area, balance_profile, context, benefit_metrics, balance_jar_order)

func is_empty() -> bool:
func resolve_order_template(
	definition: SpaceSkillDefinition,
	jar_world_options: Dictionary,
	selected_control_area: String
) -> Dictionary:
	if definition == null or definition.jar_order_template_id == &"":
		return {}
	if not definition.allowed_control_areas.has(selected_control_area):
		return {}
	var template_name := definition.core_order_template_name()
	var raw_templates: Variant = jar_world_options.get("orderTemplates", null)
	if not (raw_templates is Array):
		push_error("Selected workshop world has no Core orderTemplates array")
		return {}
	var matched_template: Dictionary = {}
	for raw_template in raw_templates:
		if raw_template is Dictionary and String(raw_template.get("name", "")) == template_name:
			matched_template = raw_template
			break
	if matched_template.is_empty():
		push_error("Skill exact Core order template is missing: " + template_name)
		return {}
	var requirements: Variant = matched_template.get("requirements", null)
	var order_type := String(matched_template.get("type", ""))
	if not ["A", "B"].has(order_type) or not (requirements is Array) or requirements.is_empty():
		return {}
	var allowed_shapes: Variant = jar_world_options.get("shapes", null)
	if not (allowed_shapes is Array):
		return {}
	var shape_vocabulary := {}
	for raw_shape in allowed_shapes:
		shape_vocabulary[String(raw_shape)] = true
	var total_count := requirements.size()
	var primary_count := 0
	for requirement in requirements:
		if not (requirement is Dictionary):
			return {}
		var shape := String(requirement.get("shape", "")).strip_edges()
		if shape.is_empty() or not shape_vocabulary.has(shape):
			return {}
		if shape == String(definition.primary_shape):
			primary_count += 1
		var liquid := String(requirement.get("liquid", "")).strip_edges()
		if not liquid.is_empty() and not (jar_world_options.get("liquids", []) as Array).has(liquid):
			return {}
	if primary_count * 2 <= total_count:
		push_error("Core order template must give the skill primary shape a strict majority")
		return {}
	return {
		"type": order_type,
		"area": selected_control_area,
		"cooldownDurationLogicalMilli": definition.jar_cooldown_logical_milli,
		"requirements": requirements.duplicate(true)
	}

	return _definitions.is_empty()

func definition_count() -> int:
	return _definitions.size()

func _key(skill_id: String, version: int) -> String:
	return "%s@%d" % [skill_id, version]
