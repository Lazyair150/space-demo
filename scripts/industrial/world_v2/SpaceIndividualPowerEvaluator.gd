extends RefCounted
class_name SpaceIndividualPowerEvaluator
## Converts real subsystem definition behavior into named raw metrics, then delegates
## normalization and rarity-scale scoring to that subsystem's exact versioned model.
## This class defines no shared balance weights, score bands, or growth multipliers.

static func evaluate_parser(
	definition: SpaceOreParserDefinition,
	shape_vocabulary: Array,
	model: SpaceIndividualPowerModelDefinition
) -> Dictionary:
	if definition == null:
		return _failure("parser evaluation requires a parser definition")
	return evaluate_parser_profile(definition.build_runtime_profile(), shape_vocabulary, model)

## Evaluate the exact effective runtime profile, including Owned Instance growth.
## Rates and progress thresholds are read after composition; output throughput therefore
## reflects production percentage, parser speed, and progress required per Jar together.
static func evaluate_effective_parser(
	definition: SpaceOreParserDefinition,
	instance: SpaceOwnedProgressionInstance,
	shape_vocabulary: Array,
	model: SpaceIndividualPowerModelDefinition
) -> Dictionary:
	var effective_profile := SpaceProgressionRuntimeProfileComposer.compose_parser(
		definition, instance, shape_vocabulary
	)
	if effective_profile.is_empty():
		return _failure("parser Owned Instance growth could not be composed into a valid runtime profile")
	return evaluate_parser_profile(effective_profile, shape_vocabulary, model)

static func evaluate_parser_profile(
	profile: Dictionary,
	shape_vocabulary: Array,
	model: SpaceIndividualPowerModelDefinition
) -> Dictionary:
	if model == null or model.item_kind != "ore_parser":
		return _failure("parser evaluation requires a matching ore-parser power model")
	var definition := SpaceOreParserDefinition.from_runtime_profile(profile)
	var errors := definition.get_validation_errors(shape_vocabulary)
	if not errors.is_empty():
		return _failure("; ".join(errors))
	var percentage := float(definition.production_percentage)
	var metrics := {
		"production_percentage": percentage,
		"shape_count": float(shape_vocabulary.size())
	}
	var total_nominal_rate := 0.0
	var total_effective_rate := 0.0
	var total_progress := 0.0
	for raw_shape in shape_vocabulary:
		var shape := String(raw_shape)
		var nominal_rate := float(definition.shape_processing_rate_per_second[shape])
		var effective_rate := nominal_rate * percentage / 100.0
		var progress := float(definition.progress_per_jar_by_shape[shape])
		metrics["processing_rate." + shape] = nominal_rate
		metrics["effective_processing_rate." + shape] = effective_rate
		metrics["progress_required_per_jar." + shape] = progress
		metrics["throughput_per_jar." + shape] = effective_rate / progress
		total_nominal_rate += nominal_rate
		total_effective_rate += effective_rate
		total_progress += progress
	metrics["average_processing_rate"] = total_nominal_rate / float(shape_vocabulary.size())
	metrics["average_effective_processing_rate"] = total_effective_rate / float(shape_vocabulary.size())
	metrics["average_progress_required_per_jar"] = total_progress / float(shape_vocabulary.size())
	return _score(model, metrics)

static func evaluate_workshop(
	definition: SpaceWorkshopDefinition,
	shape_vocabulary: Array,
	liquid_vocabulary: Array,
	model: SpaceIndividualPowerModelDefinition
) -> Dictionary:
	if definition == null or model == null or model.item_kind != "workshop":
		return _failure("workshop evaluation requires a workshop definition and matching model")
	var errors := definition.get_validation_errors()
	if not errors.is_empty():
		return _failure("; ".join(errors))
	if shape_vocabulary.is_empty() or liquid_vocabulary.is_empty():
		return _failure("workshop evaluation requires exact non-empty Jar shape and liquid vocabularies")
	for mark in definition.base_marks + definition.additional_marks:
		if not shape_vocabulary.has(mark):
			return _failure("workshop marks contain a shape outside the evaluated world vocabulary: " + mark)
	for banned_liquid in definition.banned_liquids:
		if not liquid_vocabulary.has(banned_liquid):
			return _failure("workshop Ban contains a liquid outside the evaluated world vocabulary: " + banned_liquid)
	var metrics := {
		"max_jars": float(definition.max_jars),
		"max_liquids": float(definition.max_liquids),
		# -1 is a Core fallback sentinel, not a physical capacity. Encode the absence
		# of an explicit limit as zero and preserve the fallback choice separately.
		"liquid_staging_capacity": maxf(0.0, float(definition.liquid_staging_capacity)),
		"uses_core_staging_fallback": 1.0 if definition.liquid_staging_capacity < 0 else 0.0
	}
	# Preserve the identity of each rule instead of collapsing different marks/Bans
	# into counts that would make unlike workshop configurations look equivalent.
	for raw_shape in shape_vocabulary:
		var shape := String(raw_shape)
		metrics["base_mark." + shape] = 1.0 if definition.base_marks.has(shape) else 0.0
		metrics["additional_mark." + shape] = 1.0 if definition.additional_marks.has(shape) else 0.0
	for raw_liquid in liquid_vocabulary:
		var liquid := String(raw_liquid)
		metrics["ban." + liquid] = 1.0 if definition.banned_liquids.has(liquid) else 0.0
	return _score(model, metrics)


## Evaluate the actual post-growth local rules, not the base workshop definition.
## Capacity metrics are raw observations only; their power direction/weight remains
## unconfigured until a reference workload and Master/Slave role context are authored.
static func evaluate_effective_workshop(
	definition: SpaceWorkshopDefinition,
	instance: SpaceOwnedProgressionInstance,
	shape_vocabulary: Array,
	liquid_vocabulary: Array,
	model: SpaceIndividualPowerModelDefinition
) -> Dictionary:
	var effective := SpaceProgressionRuntimeProfileComposer.compose_workshop(
		definition, instance, shape_vocabulary
	)
	if effective.is_empty():
		return _failure("workshop Owned Instance growth could not be composed into valid local rules")
	var effective_definition := SpaceWorkshopDefinition.new()
	effective_definition.workshop_id = definition.workshop_id
	effective_definition.definition_version = definition.definition_version
	effective_definition.display_name = String(effective.get("name", ""))
	effective_definition.base_marks = effective.get("baseMarks", []).duplicate()
	effective_definition.additional_marks = effective.get("additionalMarks", []).duplicate()
	effective_definition.banned_liquids = effective.get("ban", []).duplicate()
	effective_definition.max_jars = int(effective.get("maxJars", 0))
	effective_definition.max_liquids = int(effective.get("maxLiquids", 0))
	effective_definition.liquid_staging_capacity = int(effective.get("liquidStagingCapacity", -1))
	return evaluate_workshop(effective_definition, shape_vocabulary, liquid_vocabulary, model)

static func evaluate_skill(
	definition: SpaceSkillDefinition,
	benefit_metrics: Dictionary,
	balance_context: Dictionary,
	balance_profile: SpaceSkillBalanceProfile,
	model: SpaceIndividualPowerModelDefinition,
	jar_world_options: Dictionary = {}
) -> Dictionary:
	if definition == null or model == null or model.item_kind != "skill":
		return _failure("skill evaluation requires a skill definition and matching model")
	if not definition.is_valid() or benefit_metrics.is_empty() or balance_profile == null or not balance_profile.is_valid():
		return _failure("skill definition, benefit metrics or balance profile is invalid")
	if not bool(balance_context.get("valid", false)) or float(balance_context.get("expectedBattleDurationLogicalMilli", 0.0)) <= 0.0:
		return _failure("skill power evaluation requires a valid expected battle context")
	var selected_area := String(definition.allowed_control_areas[0])
	var runtime_order := definition.build_jar_order(selected_area)
	if runtime_order.is_empty():
		return _failure("skill could not materialize its Jar order contract")
	var balance_order := runtime_order
	if definition.jar_order_template_id != &"":
		balance_order = SpaceSkillCatalog.new().resolve_order_template(
			definition, jar_world_options, selected_area
		)
		if balance_order.is_empty():
			return _failure("skill exact Core order template is missing or invalid in the selected world")
	var report := SpaceSkillBalanceModel.evaluate(benefit_metrics, balance_order, balance_context, balance_profile)
	if not bool(report.get("valid", false)):
		return _failure(String(report.get("reason", "skill balance model rejected the definition")))
	var cost: Dictionary = report.get("costBreakdown", {})
	var difficulty_ratio := float(report.get("difficultyRatio", 0.0))
	var metrics := {
		"benefit_score": float(report.get("benefitScore", 0.0)),
		"target_difficulty": float(report.get("targetDifficulty", 0.0)),
		"actual_difficulty": float(report.get("actualDifficulty", 0.0)),
		"difficulty_overcost_deviation": maxf(difficulty_ratio - 1.0, 0.0),
		"difficulty_undercost_deviation": maxf(1.0 - difficulty_ratio, 0.0),
		"activation_frequency_multiplier": float(report.get("activationFrequencyMultiplier", 0.0)),
		"expected_activations": float(report.get("expectedActivations", 0.0)),
		"jar_count": float(cost.get("jarCount", 0)),
		"liquid_jar_count": float(cost.get("liquidJarCount", 0)),
		"distinct_liquid_count": float(cost.get("distinctLiquidCount", 0)),
		"distinct_shape_count": float(cost.get("distinctShapeCount", 0)),
		"cooldown_logical_milli": float(definition.jar_cooldown_logical_milli),
		"order_type_b": 1.0 if String(balance_order.get("type", "")) == "B" else 0.0
	}
	var scored := _score(model, metrics)
	if bool(scored.get("success", false)):
		scored["balanceReport"] = report
		scored["benefitMetrics"] = benefit_metrics.duplicate(true)
		scored["balanceContext"] = balance_context.duplicate(true)
	return scored

## Re-evaluate a skill after one exact Owned Instance's growth has been composed.
## The composer re-runs the benefit-to-Jar balance contract; growth that makes the skill
## undercosted is rejected before a power score can be assigned.
static func evaluate_effective_skill(
	definition: SpaceSkillDefinition,
	instance: SpaceOwnedProgressionInstance,
	benefit_metrics: Dictionary,
	balance_context: Dictionary,
	balance_profile: SpaceSkillBalanceProfile,
	model: SpaceIndividualPowerModelDefinition,
	jar_world_options: Dictionary = {}
) -> Dictionary:
	if definition == null or instance == null or instance.item_kind != "skill":
		return _failure("effective skill evaluation requires its exact Owned Instance")
	if instance.definition_id != definition.skill_id or instance.definition_version != definition.definition_version:
		return _failure("skill Owned Instance definition identity does not match the evaluated Definition")
	if definition.allowed_control_areas.is_empty():
		return _failure("skill has no allowed control area for effective power evaluation")
	var area := String(definition.allowed_control_areas[0])
	var runtime_order := definition.build_jar_order(area)
	if runtime_order.is_empty():
		return _failure("skill runtime Jar order could not be built")
	var balance_order := runtime_order
	if definition.jar_order_template_id != &"":
		balance_order = SpaceSkillCatalog.new().resolve_order_template(definition, jar_world_options, area)
		if balance_order.is_empty():
			return _failure("skill exact Core order template is missing from the frozen World options")
	var binding := definition.create_order_binding(
		"effective-power-evaluation", area, balance_profile,
		balance_context, benefit_metrics, balance_order
	)
	if binding.is_empty():
		return _failure("base skill binding failed its benefit-to-Jar balance contract")
	var effective_binding := SpaceProgressionRuntimeProfileComposer.compose_skill_binding(
		binding, definition, instance, balance_profile, jar_world_options
	)
	if effective_binding.is_empty():
		return _failure("skill growth violates its subsystem attributes or benefit-to-Jar balance contract")
	var evaluated := evaluate_skill(
		definition,
		effective_binding.get("benefitProfile", {}),
		balance_context,
		balance_profile,
		model,
		jar_world_options
	)
	if not bool(evaluated.get("success", false)):
		return evaluated
	evaluated["ownedInstance"] = instance.build_frozen_snapshot()
	evaluated["effectiveBinding"] = effective_binding
	return evaluated

static func _score(model: SpaceIndividualPowerModelDefinition, metrics: Dictionary) -> Dictionary:
	if model == null or not model.get_validation_errors().is_empty():
		return _failure("subsystem power model is invalid or not authored")
	var scored := model.calculate_power_score(metrics)
	if not bool(scored.get("success", false)):
		return _failure(String(scored.get("reason", "subsystem model rejected the metric payload")))
	return {
		"success": true,
		"itemKind": model.item_kind,
		"powerModelId": String(model.model_id),
		"powerModelVersion": model.definition_version,
		"powerMetrics": metrics.duplicate(true),
		"powerScore": float(scored.powerScore)
	}

static func _failure(reason: String) -> Dictionary:
	return {"success": false, "reason": reason}
