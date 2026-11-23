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
		"effective_processing_rate.round": 1.0,
		"throughput_per_jar.round": 0.5,
		"processing_rate.square": 4.0,
		"effective_processing_rate.square": 2.0,
		"progress_required_per_jar.square": 1.0,
		"throughput_per_jar.square": 2.0,
		"average_processing_rate": 3.0,
		"average_effective_processing_rate": 1.5,
		"average_progress_required_per_jar": 1.5
	}
	var model := _model("probe.parser.power", "ore_parser", metrics)
	var result := SpaceIndividualPowerEvaluator.evaluate_parser(parser, ["round", "square"], model)
	if not bool(result.get("success", false)) or result.get("powerMetrics", {}) != metrics:
		return false
	var pool := _pool_for_model("probe.parser.pool", "ore_parser", model)
	var built := SpaceRoguelikeIndividualPoolEntryBuilder.append_parser(pool, parser, ["round", "square"], "common", 1.0)
	if not bool(built.get("success", false)) or not pool.is_valid():
		return false
	var owned_parser := SpaceOwnedProgressionInstance.new()
	owned_parser.instance_id = &"probe.parser.owned"
	owned_parser.item_kind = "ore_parser"
	owned_parser.definition_id = parser.parser_id
	owned_parser.definition_version = parser.definition_version
	owned_parser.growth_attributes = {
		"shapeProcessingRateMultiplier": 1.5,
		"progressPerJarMultiplier": 0.5,
		"productionPercentageBonus": 10
	}
	var effective := SpaceIndividualPowerEvaluator.evaluate_effective_parser(
		parser, owned_parser, ["round", "square"], model
	)
	if not bool(effective.get("success", false)):
		return false
	var effective_metrics: Dictionary = effective.powerMetrics
	return is_equal_approx(float(effective_metrics["production_percentage"]), 60.0) \
		and is_equal_approx(float(effective_metrics["effective_processing_rate.round"]), 1.8) \
		and is_equal_approx(float(effective_metrics["throughput_per_jar.round"]), 1.8) \
		and is_equal_approx(float(effective_metrics["throughput_per_jar.square"]), 7.2)

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
		"liquid_staging_capacity": 0.0,
		"uses_core_staging_fallback": 1.0,
		"base_mark_count": 1.0,
		"additional_mark_count": 0.0,
		"banned_liquid_count": 0.0
	}
	var model := _model("probe.workshop.power", "workshop", metrics)
	var result := SpaceIndividualPowerEvaluator.evaluate_workshop(workshop, ["round"], ["water", "fuel"], model)
	if not bool(result.get("success", false)) or result.get("powerMetrics", {}) != metrics:
		return false
	var pool := _pool_for_model("probe.workshop.pool", "workshop", model)
	var built := SpaceRoguelikeIndividualPoolEntryBuilder.append_workshop(pool, workshop, ["round"], ["water", "fuel"], "common", 1.0)
	return bool(built.get("success", false)) and pool.is_valid()

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
		"difficulty_overcost_deviation": 2.5 / (1.0 + pow(0.2, 1.25)) - 1.0,
		"difficulty_undercost_deviation": 0.0,
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
	if not bool(result.get("success", false)) or result.get("powerMetrics", {}).size() != model_metrics.size():
		return false
	var pool := _pool_for_model("probe.skill.pool", "skill", model)
	var built := SpaceRoguelikeIndividualPoolEntryBuilder.append_skill(pool, skill, benefit, context, balance, "common", 1.0)
	if not bool(built.get("success", false)) or not pool.is_valid():
		return false

	# Template-backed skill power must use the Core template's actual requirements and type.
	var template_skill := skill.duplicate(true) as SpaceSkillDefinition
	template_skill.jar_order_type = "A"
	template_skill.jar_requirements.clear()
	template_skill.jar_order_template_id = &"probe.skill.offense"
	template_skill.jar_order_template_version = 2
	var world_options := {
		"shapes": ["round", "square"],
		"liquids": ["water", "fuel"],
		"orderTemplates": [{
			"name": "probe.skill.offense@2",
			"type": "B",
			"requirements": [
				{"shape": "round"}, {"shape": "square"}, {"shape": "round", "liquid": "water"}
			]
		}]
	}
	var template_report := SpaceIndividualPowerEvaluator.evaluate_skill(
		template_skill, benefit, context, balance, model, world_options
	)
	if not bool(template_report.get("success", false)) or float(template_report.powerMetrics.get("jar_count", 0.0)) != 3.0 or float(template_report.powerMetrics.get("order_type_b", 0.0)) != 1.0:
		return false
	var template_pool := _pool_for_model("probe.skill.template.pool", "skill", model)
	var template_entry := SpaceRoguelikeIndividualPoolEntryBuilder.append_skill(
		template_pool, template_skill, benefit, context, balance, "common", 1.0, [], world_options
	)
	return bool(template_entry.get("success", false)) \
		and String(template_entry.entry.get("orderTemplateName", "")) == "probe.skill.offense@2" \
		and template_pool.is_valid()

static func _model(id: String, kind: String, metrics: Dictionary) -> SpaceIndividualPowerModelDefinition:
	var model := SpaceIndividualPowerModelDefinition.new()
	model.model_id = StringName(id)
	model.definition_version = 1
	model.item_kind = kind
	for key in metrics:
		var minimum := 0.0
		model.metric_dimensions[key] = {
			"minimum": minimum,
			"maximum": 100000.0,
			"weight": 1.0,
			"higherIsBetter": not ["difficulty_overcost_deviation", "difficulty_undercost_deviation"].has(String(key))
		}
	return model

static func _pool_for_model(id: String, kind: String, model: SpaceIndividualPowerModelDefinition) -> SpaceRoguelikeIndividualPool:
	var pool := SpaceRoguelikeIndividualPool.new()
	pool.pool_id = StringName(id)
	pool.definition_version = 1
	pool.power_model_id = model.model_id
	pool.power_model_version = model.definition_version
	pool.item_kind = kind
	pool.power_model = model
	pool.power_bands = {"common": {"minimum": 0.0, "maximum": 10.0}}
	return pool
