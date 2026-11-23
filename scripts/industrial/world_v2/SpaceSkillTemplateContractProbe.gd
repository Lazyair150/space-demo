extends RefCounted
class_name SpaceSkillTemplateContractProbe
## Verifies the Space -> Core template-key boundary without synthesizing gameplay balance assets.

static func run() -> bool:
	var definition := SpaceSkillDefinition.new()
	definition.skill_id = &"probe.template.skill"
	definition.definition_version = 1
	definition.display_name = "Template Skill Probe"
	definition.ability_category = "Offense"
	definition.jar_order_template_id = &"skill.offense"
	definition.jar_order_template_version = 2
	definition.jar_cooldown_logical_milli = 2500
	definition.primary_shape = &"triangle"
	definition.allowed_control_areas = ["Active", "Passive"]
	definition.effect_definition_id = &"probe.effect"
	definition.effect_definition_version = 1
	if not definition.is_valid():
		return false

	var catalog := SpaceSkillCatalog.new()
	if not catalog.register_skill(definition):
		return false
	var world_options := {
		"shapes": ["triangle", "square"],
		"liquids": ["water", "mist"],
		"orderTemplates": [{
			"name": "skill.offense@2",
			"type": "B",
			"requirements": [
				{"shape": "triangle"},
				{"shape": "square"},
				{"shape": "triangle", "liquid": "water"}
			]
		}]
	}
	var resolved := catalog.resolve_order_template(definition, world_options, "Active")
	if resolved.is_empty() or String(resolved.type) != "B" or resolved.requirements.size() != 3:
		return false
	var runtime_order := definition.build_jar_order("Active")
	if String(runtime_order.get("templateName", "")) != "skill.offense@2":
		return false
	var legacy_mixture := definition.duplicate(true) as SpaceSkillDefinition
	legacy_mixture.jar_requirements = [{"shape": "triangle"}]
	if legacy_mixture.is_valid():
		return false
	if runtime_order.has("type") or runtime_order.has("requirements"):
		return false
	if definition.allowed_control_areas.has("Passive") and catalog.resolve_order_template(
		definition, world_options, "Passive"
	).is_empty():
		return false

	var wrong_version := world_options.duplicate(true)
	wrong_version.orderTemplates[0].name = "skill.offense@1"
	if not catalog.resolve_order_template(definition, wrong_version, "Active").is_empty():
		return false
	var no_majority := world_options.duplicate(true)
	no_majority.orderTemplates[0].requirements = [
		{"shape": "triangle"}, {"shape": "square"}, {"shape": "square"}
	]
	if not catalog.resolve_order_template(definition, no_majority, "Active").is_empty():
		return false
	var unknown_liquid := world_options.duplicate(true)
	unknown_liquid.orderTemplates[0].requirements[2].liquid = "unconfigured"
	if not catalog.resolve_order_template(definition, unknown_liquid, "Active").is_empty():
		return false
	return true
