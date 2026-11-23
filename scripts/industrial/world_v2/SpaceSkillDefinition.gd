extends Resource
class_name SpaceSkillDefinition
## Unified player-facing capability definition. All Space combat capabilities are skills; Jar receives only the nested jarOrder contract.

enum ControlArea { ACTIVE, PASSIVE }
enum ActivationPolicy { MANUAL, AUTOMATIC }

@export var skill_id: StringName = &""
@export var definition_version: int = 1
@export var display_name: String = ""
@export var display_icon: Texture2D
@export_multiline var description: String = ""
@export_enum("Offense", "Defense", "Support", "Reconnaissance", "Utility") var ability_category: String = "Offense"

## Jar-owned execution contract. Keep this data free of Space effect semantics.
## Exact versioned Core order template identity. Core receives only the canonical template key.
## A non-empty template ID selects the production path; legacy inline requirements are then forbidden.
@export var jar_order_template_id: StringName = &""
@export var jar_order_template_version: int = 0
@export_enum("A", "B") var jar_order_type: String = "A" # Legacy development-only fallback.
@export_range(0, 2147483647, 1) var jar_cooldown_logical_milli: int = 0
@export var jar_requirements: Array[Dictionary] = [] # Legacy development-only fallback.

## Space-side visual identity for the order's principal Jar shape; never sent inside jarOrder.
@export var primary_shape: StringName = &""

## Player-facing control assignment. Passive scheduling is owned by Jar Core.
@export var allowed_control_areas: Array[String] = ["Active", "Passive"]

## Space-owned benefit/effect binding. Buff is the first executor, not the only future type.
@export var effect_definition_id: StringName = &""
@export var effect_definition_version: int = 1
@export var effect_parameters: Dictionary = {}
## Explicit effect-parameter -> benefit-dimension mapping used when growth changes balance-relevant values.
@export var effect_parameter_benefit_dimensions: Dictionary = {}

func is_valid() -> bool:
	if skill_id == &"" or definition_version <= 0 or display_name.strip_edges().is_empty():
		return false
	if not ["Offense", "Defense", "Support", "Reconnaissance", "Utility"].has(ability_category):
		return false
	if jar_cooldown_logical_milli < 0:
		return false
	if jar_order_template_id != &"":
		if jar_order_template_version <= 0 or not jar_requirements.is_empty():
			return false
	else:
		if not ["A", "B"].has(jar_order_type) or jar_requirements.is_empty():
			return false
	if allowed_control_areas.is_empty():
		return false
	for area in allowed_control_areas:
		if not ["Active", "Passive"].has(area):
			return false
	if effect_definition_id == &"" or effect_definition_version <= 0:
		return false
	for parameter_key in effect_parameter_benefit_dimensions:
		if not effect_parameters.has(parameter_key) or String(parameter_key).strip_edges().is_empty() or String(effect_parameter_benefit_dimensions[parameter_key]).strip_edges().is_empty():
			return false
	if primary_shape == &"":
		return false
	if jar_order_template_id != &"":
		return true # Actual template shape mix is validated against the selected World vocabulary by SkillCatalog.
	var primary_shape_found := false
	for requirement in jar_requirements:
		var requirement_shape := String(requirement.get("shape", "")).strip_edges()
		if requirement_shape == String(primary_shape):
			primary_shape_found = true
		if requirement_shape.is_empty():
			return false
		if int(requirement.get("count", 1)) <= 0:
			return false
	if not primary_shape_found:
		return false
	return true

func has_majority_shape(shape: String) -> bool:
	if shape.strip_edges().is_empty():
		return false
	var total := 0
	var matching := 0
	for requirement in jar_requirements:
		if not (requirement is Dictionary):
			return false
		var count := int(requirement.get("count", 1))
		if count <= 0:
			return false
		total += count
		if String(requirement.get("shape", "")).strip_edges() == shape:
			matching += count
	return total > 0 and matching * 2 > total

func is_valid_for_shape_profile(profile: SpaceAbilityShapeProfile) -> bool:
	return profile != null and profile.validate_skill(self).is_empty()

func core_order_template_name() -> String:
	if jar_order_template_id == &"" or jar_order_template_version <= 0:
		return ""
	return "%s@%d" % [String(jar_order_template_id), jar_order_template_version]

func build_jar_order(selected_control_area: String) -> Dictionary:
	if not is_valid() or not allowed_control_areas.has(selected_control_area):
		return {}
	if jar_order_template_id != &"":
		return {
			"templateName": core_order_template_name(),
			"area": selected_control_area,
			"cooldownDurationLogicalMilli": jar_cooldown_logical_milli
		}
	var expanded_requirements: Array[Dictionary] = []
	for requirement in jar_requirements:
		var count := int(requirement.get("count", 1))
		var normalized := {"shape": String(requirement.get("shape", "")).strip_edges()}
		var liquid := String(requirement.get("liquid", "")).strip_edges()
		if not liquid.is_empty():
			normalized["liquid"] = liquid
		for _i in range(count):
			expanded_requirements.append(normalized.duplicate(true))
	return {
		"type": jar_order_type,
		"area": selected_control_area,
		"cooldownDurationLogicalMilli": jar_cooldown_logical_milli,
		"requirements": expanded_requirements
	}

func create_order_binding(order_definition_key: String, selected_control_area: String, balance_profile: SpaceSkillBalanceProfile, balance_context: Dictionary, benefit_metrics: Dictionary, balance_jar_order: Dictionary = {}) -> Dictionary:
	if not is_valid() or order_definition_key.strip_edges().is_empty():
		return {}
	if not allowed_control_areas.has(selected_control_area):
		return {}
	if balance_profile == null or not balance_profile.is_valid():
		return {}
	if not bool(balance_context.get("valid", false)) or float(balance_context.get("expectedBattleDurationLogicalMilli", 0.0)) <= 0.0:
		return {}
	var activation_policy := "Manual" if selected_control_area == "Active" else "Automatic"
	var jar_order := build_jar_order(selected_control_area)
	if benefit_metrics.is_empty():
		return {}
	var evaluated_order := balance_jar_order if not balance_jar_order.is_empty() else jar_order
	var balance_report := SpaceSkillBalanceModel.evaluate(benefit_metrics, evaluated_order, balance_context, balance_profile)
	if not balance_report.get("valid", false):
		push_error("Skill balance evaluation failed: " + String(balance_report.get("reason", "unknown")))
		return {}
	return {
		"orderDefinitionKey": order_definition_key,
		"presentation": {"primaryShape": String(primary_shape)} if primary_shape != &"" else {},
		"skillDefinitionId": String(skill_id),
		"skillDefinitionVersion": definition_version,
		"abilityCategory": ability_category,
		"jarOrder": jar_order,
		"jarOrderTemplate": {
			"templateId": String(jar_order_template_id),
			"templateVersion": jar_order_template_version,
			"templateName": core_order_template_name()
		} if jar_order_template_id != &"" else {},
		"skillControl": {
			"area": selected_control_area,
			"activationPolicy": activation_policy
		},
		"benefitProfile": benefit_metrics.duplicate(true),
		"balanceReport": balance_report,
		"balanceProfile": {
			"profileId": String(balance_profile.profile_id),
			"profileVersion": balance_profile.profile_version
		},
		"balanceContext": balance_context.duplicate(true),
		"effectBinding": {
			"effectDefinitionId": String(effect_definition_id),
			"effectDefinitionVersion": effect_definition_version,
			"effectParameters": effect_parameters.duplicate(true)
		}
	}
