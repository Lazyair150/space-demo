extends RefCounted
class_name SpaceIndividualPowerEvaluatorProbe
## Synthetic adapter tests. They verify metric provenance, not production balance values.

static func run() -> bool:
	if not _probe_parser() or not _probe_workshop() or not _probe_skill():
		return false
	return true

static func _probe_parser() -> bool:
	var parser := SpaceOreParserDefinition.new()
	parser.parser_id = &"probe.parser"
	parser.definition_version = 1
	parser.display_name = "Probe Parser"
	parser.production_percentage = 50
	parser.shape_processing_rate_per_second = {"round": 2.0, "square": 4.0}
	parser.progress_per_jar_by_shape = {"round": 2.0, "square": 1.0}
	var metrics := {
		"production_percentage": 50.0,
		"shape_count": 2.0,
		"processing_rate.round": 2.0,
		"progress_required_per_jar.round": 2.0,
		"throughput_per_jar.round": 1.0,
		"processing_rate.square": 4.0,
		"progress_required_per_jar.square": 1.0,
		"throughput_per_jar.square": 4.0,
		"average_processing_rate": 3.0,
		"average_progress_required_per_jar": 1.5
	}
	var model := _model("probe.parser.power", "ore_parser", metrics)
	var result := SpaceIndividualPowerEvaluator.evaluate_parser(parser, ["round", "square"], model)
	return bool(result.get("success", false)) and result.get("powerMetrics", {}) == metrics

static func _probe_workshop() -> bool:
	var workshop := SpaceWorkshopDefinition.new()
	workshop.workshop_id = &"probe.workshop"
	workshop.definition_version = 1
	workshop.display_name = "Probe Workshop"
	workshop.base_marks = ["round"]
	workshop.max_jars = 4
	workshop.max_liquids = 8
	workshop.liquid_staging_capacity = -1
	var metrics := {
		"max_jars": 4.0,
		"max_liquids": 8.0,
		"liquid_staging_capacity": -1.0,
		"uses_core_staging_fallback": 1.0,
		"base_mark_count": 1.0,
		"additional_mark_count": 0.0,
		"banned_liquid_count": 0.0
	}
	var model := _model("probe.workshop.power", "workshop", metrics)
	var result := SpaceIndividualPowerEvaluator.evaluate_workshop(workshop, model)
	return bool(result.get("success", false)) and result.get("powerMetrics", {}) == metrics

static func _probe_skill() -> bool:
	var skill := SpaceSkillDefinition.new()
	skill.skill_id = &"probe.skill"
	skill.definition_version = 1
	skill.display_name = "Probe Skill"
	skill.ability_category = "Offense"
	skill.jar_order_type = "A"
	skill.jar_cooldown_logical_milli = 10000
	skill.jar_requirements = [{"shape": "round", "count": 1}]
	skill.primary_shape = &"round"
	skill.allowed_control_areas = ["Active"]
	skill.effect_definition_id = &"probe.effect"
	var benefit := {"power": 2.0}
	var context := {"valid": true, "expectedBattleDurationLogicalMilli": 60000.0}
	var balance := SpaceSkillBalanceProfile.new()
	var model_metrics := {
		"benefit_score": 0.2,
		"target_difficulty": 1.0 + pow(0.2, 1.25),
		"actual_difficulty": 2.5,
		"difficulty_ratio": 2.5 / (1.0 + pow(0.2, 1.25)),
		"activation_frequency_multiplier": 1.0,
		"expected_activations": 6.0,
		"jar_count": 1.0,
		"liquid_jar_count": 0.0,
		"distinct_liquid_count": 0.0,
		"distinct_shape_count": 1.0,
		"cooldown_logical_milli": 10000.0,
		"order_type_b": 0.0
	}
	var model := _model("probe.skill.power", "skill", model_metrics)
	var result := SpaceIndividualPowerEvaluator.evaluate_skill(skill, benefit, context, balance, model)
	return bool(result.get("success", false)) and result.get("powerMetrics", {}).size() == model_metrics.size()

static func _model(id: String, kind: String, metrics: Dictionary) -> SpaceIndividualPowerModelDefinition:
	var model := SpaceIndividualPowerModelDefinition.new()
	model.model_id = StringName(id)
	model.definition_version = 1
	model.item_kind = kind
	for key in metrics:
		var minimum := -1.0 if String(key) == "liquid_staging_capacity" else 0.0
		model.metric_dimensions[key] = {
			"minimum": minimum,
			"maximum": 100000.0,
			"weight": 1.0,
			"higherIsBetter": true
		}
	return model
