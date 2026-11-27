extends RefCounted
class_name SpaceSkillBalanceModel
## Evaluates whether a skill's player-visible benefit is supported by its real Jar cost structure.
## It does not invent or mutate recipes: the evaluated requirements are the exact Jar requirements
## that will be materialized into the battle loadout.

static func evaluate(
	benefit: Dictionary,
	jar_order: Dictionary,
	context: Dictionary,
	profile: SpaceSkillBalanceProfile
) -> Dictionary:
	if profile == null or not profile.is_valid():
		return _failure("invalid balance profile")
	var requirements: Variant = jar_order.get("requirements", null)
	if not (requirements is Array) or requirements.is_empty():
		return _failure("Jar requirements must be a non-empty array")

	var benefit_score := _benefit_score(benefit, profile)
	var cooldown_milli := float(jar_order.get("cooldownDurationLogicalMilli", -1.0))
	if cooldown_milli < 0.0:
		return _failure("Jar cooldown cannot be negative")
	var effective_cooldown := maxf(cooldown_milli, profile.cooldown_floor_logical_milli)
	var battle_duration_milli := float(context.get("expectedBattleDurationLogicalMilli", 0.0))
	var expected_activations := 0.0
	var reference_activations := 0.0
	var frequency_multiplier := 1.0
	if battle_duration_milli > 0.0:
		expected_activations = ceil(battle_duration_milli / effective_cooldown)
		reference_activations = ceil(battle_duration_milli / profile.cooldown_reference_logical_milli)
		frequency_multiplier = minf(expected_activations / maxf(reference_activations, 1.0), profile.cooldown_max_frequency_multiplier)
	else:
		# Compatibility for isolated formula probes; production loadouts require a duration-bearing context.
		frequency_multiplier = minf(profile.cooldown_reference_logical_milli / effective_cooldown, profile.cooldown_max_frequency_multiplier)
	benefit_score *= frequency_multiplier
	if benefit_score < 0.0:
		return _failure("benefit profile contains invalid values")

	var jar_count: int = requirements.size()
	var liquid_jar_count := 0
	var shapes := {}
	var liquids := {}
	var resource_multiplier_total := 0.0
	for raw in requirements:
		if not (raw is Dictionary):
			return _failure("Jar requirement entry must be a dictionary")
		var requirement: Dictionary = raw
		var shape := String(requirement.get("shape", "")).strip_edges()
		if shape.is_empty():
			return _failure("Jar requirement is missing shape")
		shapes[shape] = true
		var shape_multiplier := float(profile.shape_difficulty_multipliers.get(shape, 1.0))
		if shape_multiplier <= 0.0:
			return _failure("shape difficulty multiplier must be positive")
		resource_multiplier_total += shape_multiplier
		var liquid := String(requirement.get("liquid", "")).strip_edges()
		if not liquid.is_empty():
			liquid_jar_count += 1
			liquids[liquid] = true
			var liquid_multiplier := float(profile.liquid_difficulty_multipliers.get(liquid, 1.0))
			if liquid_multiplier <= 0.0:
				return _failure("liquid difficulty multiplier must be positive")
			resource_multiplier_total += liquid_multiplier

	var distinct_shape_count := shapes.size()
	var distinct_liquid_count := liquids.size()
	var order_type := String(jar_order.get("type", ""))
	if not ["A", "B"].has(order_type):
		return _failure("unsupported Jar order type")

	var workshop_operations := maxf(0.0, float(context.get("workshopOperationCount", 0.0)))
	var production_pressure := maxf(0.0, float(context.get("productionPressure", 0.0)))
	var jar_component := float(jar_count) * profile.jar_base_weight
	var liquid_component := float(liquid_jar_count) * profile.liquid_jar_weight
	var liquid_diversity_component := float(distinct_liquid_count) * profile.distinct_liquid_weight
	var shape_diversity_component := float(distinct_shape_count) * profile.distinct_shape_weight
	var order_component := profile.order_type_b_weight if order_type == "B" else 0.0
	var workshop_component := workshop_operations * profile.workshop_operation_weight
	var production_component := production_pressure * profile.production_pressure_weight
	var resource_component := resource_multiplier_total
	var actual_difficulty := jar_component + liquid_component + liquid_diversity_component \
		+ shape_diversity_component + order_component + workshop_component \
		+ production_component + resource_component

	var target_difficulty := profile.curve_base_difficulty \
		+ profile.curve_coefficient * pow(benefit_score, profile.curve_exponent)
	var ratio := actual_difficulty / maxf(target_difficulty, 0.000001)
	var gap := actual_difficulty - target_difficulty
	var additional_plain_jar_equivalent := maxf(0.0, -gap) / maxf(profile.jar_base_weight + 1.0, 0.000001)
	var additional_liquid_jar_equivalent := maxf(0.0, -gap) / maxf(profile.jar_base_weight + profile.liquid_jar_weight + 2.0, 0.000001)
	return {
		"valid": true,
		"profileId": String(profile.profile_id),
		"profileVersion": profile.profile_version,
		"benefitScore": benefit_score,
		"baseBenefitScore": _benefit_score(benefit, profile),
		"cooldownLogicalMilli": cooldown_milli,
		"activationFrequencyMultiplier": frequency_multiplier,
		"expectedBattleDurationLogicalMilli": battle_duration_milli,
		"expectedActivations": expected_activations,
		"referenceActivations": reference_activations,
		"targetDifficulty": target_difficulty,
		"actualDifficulty": actual_difficulty,
		"difficultyRatio": ratio,
		"difficultyGap": gap,
		"additionalPlainJarEquivalentToReachCurve": additional_plain_jar_equivalent,
		"additionalLiquidJarEquivalentToReachCurve": additional_liquid_jar_equivalent,
		"balanceStatus": _status(ratio, profile),
		"difficultyBand": _band(actual_difficulty, profile.difficulty_bands),
		"costBreakdown": {
			"jarCount": jar_count,
			"liquidJarCount": liquid_jar_count,
			"distinctLiquidCount": distinct_liquid_count,
			"distinctShapeCount": distinct_shape_count,
			"jarComponent": jar_component,
			"liquidComponent": liquid_component,
			"liquidDiversityComponent": liquid_diversity_component,
			"shapeDiversityComponent": shape_diversity_component,
			"resourceMultiplierComponent": resource_component,
			"orderTypeComponent": order_component,
			"workshopComponent": workshop_component,
			"productionPressureComponent": production_component
		}
	}

static func _benefit_score(benefit: Dictionary, profile: SpaceSkillBalanceProfile) -> float:
	var score := 0.0
	for dimension in profile.benefit_weights:
		var value := float(benefit.get(dimension, 0.0))
		if value < 0.0:
			return -1.0
		var normalized := value / float(profile.benefit_scales[dimension])
		score += normalized * float(profile.benefit_weights[dimension])
	return score

static func _status(ratio: float, profile: SpaceSkillBalanceProfile) -> String:
	if ratio < profile.on_curve_min_ratio:
		return "undercosted"
	if ratio > profile.on_curve_max_ratio:
		return "overcosted"
	return "on_curve"

static func _band(difficulty: float, bands: Array[Dictionary]) -> String:
	var selected := ""
	for band in bands:
		if difficulty >= float(band.get("minimum", 0.0)):
			selected = String(band.get("id", ""))
	return selected

static func _failure(reason: String) -> Dictionary:
	return {"valid": false, "reason": reason}
