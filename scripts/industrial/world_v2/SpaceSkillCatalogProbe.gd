extends RefCounted
class_name SpaceSkillCatalogProbe
## Focused catalog ownership probe. Uses synthetic metadata only; no gameplay balance values.

static func run() -> bool:
	var source := SpaceSkillDefinition.new()
	source.skill_id = &"probe.skill"
	source.definition_version = 3
	source.display_name = "Probe Skill"
	source.jar_order_type = "A"
	source.jar_cooldown_logical_milli = 1000
	source.jar_requirements = [{ "shape": "probe_shape", "count": 1 }]
	source.allowed_control_areas = ["Active"]
	source.effect_definition_id = &"probe.effect"
	source.effect_definition_version = 2
	if not source.is_valid():
		return false

	var catalog := SpaceSkillCatalog.new()
	if not catalog.register_skill(source):
		return false

	# Mutating the authoring Resource after registration must not mutate the catalog.
	source.display_name = "Mutated Source"
	source.jar_requirements[0]["shape"] = "mutated_shape"
	var first := catalog.resolve_skill("probe.skill", 3)
	if first == null or first.display_name != "Probe Skill":
		return false
	if String(first.jar_requirements[0].get("shape", "")) != "probe_shape":
		return false

	# Mutating a resolved Resource must not mutate subsequent resolutions either.
	first.display_name = "Mutated Resolved Copy"
	first.jar_requirements[0]["shape"] = "mutated_resolved_shape"
	var second := catalog.resolve_skill("probe.skill", 3)
	if second == null or second.display_name != "Probe Skill":
		return false
	if String(second.jar_requirements[0].get("shape", "")) != "probe_shape":
		return false
	if catalog.resolve_skill("probe.skill", 2) != null:
		return false
	return SpaceSkillTemplateContractProbe.run()
