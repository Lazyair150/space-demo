extends RefCounted
class_name SpaceSkillBuildContextEvaluator
## Converts the selected production-device/workshop build into measurable per-skill pressure.
## Expected schema:
## ship_resource_profile.expectedStoneProgressPerSecondByShape: { shape_id: non-negative progress/second }
## device.oreParserProfile: { productionPercentage: 0..100, shapeProcessingRatePerSecond: { shape_id: progress/second } }
## shape_progress_per_jar: { shape_id: positive progress units required for one Jar }
## workshop.operationCostByOrderType: { A|B: non-negative operations per cycle }
## workshop.liquidHandlingOperationCost: non-negative operations per liquid-bearing jar.

static func evaluate(
	jar_order: Dictionary,
	production_devices: Array,
	workshop_combination: Dictionary,
	ship_resource_profile: Dictionary,
	shape_progress_per_jar: Dictionary,
	expected_battle_duration_logical_milli: float,
	profile: SpaceSkillBalanceProfile
) -> Dictionary:
	if profile == null or not profile.is_valid():
		return _failure("invalid balance profile")
	if expected_battle_duration_logical_milli <= 0.0:
		return _failure("expected battle duration must be positive")
	var requirements: Variant = jar_order.get("requirements", null)
	if not (requirements is Array) or requirements.is_empty():
		return _failure("Jar requirements must be a non-empty array")
	if production_devices.is_empty():
		return _failure("at least one selected production device is required")
	var aggregate_rates := {}
	var parser_progress_per_jar: Dictionary = {}
	var ore_parser_count := 0
	for raw_device in production_devices:
		if not (raw_device is Dictionary):
			return _failure("production device selection must be a dictionary")
		if String(raw_device.get("deviceKind", "")) != "ore_parser" and not raw_device.has("oreParserProfile"):
			continue
		ore_parser_count += 1
		var parser_profile: Variant = raw_device.get("oreParserProfile", raw_device)
		if not (parser_profile is Dictionary):
			return _failure("production device oreParserProfile must be a dictionary")
		var raw_percentage: Variant = parser_profile.get("productionPercentage", null)
		if typeof(raw_percentage) != TYPE_INT or int(raw_percentage) < 0 or int(raw_percentage) > 100:
			return _failure("ore parser productionPercentage must be an integer from 0 to 100")
		var rates: Variant = parser_profile.get("shapeProcessingRatePerSecond", null)
		var parser_progress: Variant = parser_profile.get("progressPerJarByShape", null)
		if not (rates is Dictionary) or rates.is_empty() or not (parser_progress is Dictionary) or parser_progress.is_empty():
			return _failure("ore parser must provide per-shape processing rates and progressPerJarByShape")
		parser_progress_per_jar = parser_progress.duplicate(true)
		for shape in rates:
			var raw_rate: Variant = rates[shape]
			if (typeof(raw_rate) != TYPE_INT and typeof(raw_rate) != TYPE_FLOAT) or not is_finite(float(raw_rate)) or float(raw_rate) < 0.0 or float(raw_rate) > 1000000000.0:
				return _failure("shape processing rates are outside the supported fixed-point range")
			var effective_rate := float(raw_rate) * float(raw_percentage) / 100.0
			aggregate_rates[String(shape)] = float(aggregate_rates.get(String(shape), 0.0)) + effective_rate
	if ore_parser_count != 1:
		return _failure("exactly one selected universal ore parser is required for shape production")

	var stone_rates: Variant = ship_resource_profile.get("expectedStoneProgressPerSecondByShape", null)
	if not (stone_rates is Dictionary) or stone_rates.is_empty():
		return _failure("ship resource profile must provide expectedStoneProgressPerSecondByShape")
	for shape_key in stone_rates:
		var raw_stone_rate: Variant = stone_rates[shape_key]
		if (typeof(raw_stone_rate) != TYPE_INT and typeof(raw_stone_rate) != TYPE_FLOAT) or not is_finite(float(raw_stone_rate)) or float(raw_stone_rate) < 0.0:
			return _failure("ship stone progress rates must be finite and non-negative")
	var shape_demand := {}
	var liquid_jar_count := 0
	for raw_requirement in requirements:
		if not (raw_requirement is Dictionary):
			return _failure("Jar requirement must be a dictionary")
		var requirement: Dictionary = raw_requirement
		var shape := String(requirement.get("shape", "")).strip_edges()
		if shape.is_empty():
			return _failure("Jar requirement is missing shape")
		shape_demand[shape] = int(shape_demand.get(shape, 0)) + 1
		if not String(requirement.get("liquid", "")).strip_edges().is_empty():
			liquid_jar_count += 1

	var effective_cooldown := maxf(
		float(jar_order.get("cooldownDurationLogicalMilli", 0)),
		profile.cooldown_floor_logical_milli
	)
	var expected_activations := ceil(expected_battle_duration_logical_milli / effective_cooldown)
	var battle_seconds := expected_battle_duration_logical_milli / 1000.0
	var total_required_jars := 0.0
	var total_production_capacity := 0.0
	var shape_pressure := {}
	for shape in shape_demand:
		var processor_rate := float(aggregate_rates.get(shape, 0.0))
		var stone_rate := float(stone_rates.get(shape, 0.0))
		var progress_per_jar := float(parser_progress_per_jar.get(shape, 0.0))
		if shape_progress_per_jar.has(shape) and absf(float(shape_progress_per_jar[shape]) - progress_per_jar) > 0.000001:
			return _failure("shape progress-per-Jar must match the frozen selected ore parser profile: " + shape)
		if processor_rate <= 0.0 or stone_rate <= 0.0 or progress_per_jar <= 0.0:
			return _failure("ship drops, selected processors, and Jar conversion must all support shape: " + shape)
		var effective_progress_rate := minf(processor_rate, stone_rate)
		var output_jar_rate := effective_progress_rate / progress_per_jar
		var required := float(shape_demand[shape]) * expected_activations
		var capacity := output_jar_rate * battle_seconds
		total_required_jars += required
		total_production_capacity += capacity
		shape_pressure[shape] = required / maxf(capacity, 0.000001)
		aggregate_rates[shape] = output_jar_rate

	var order_type := String(jar_order.get("type", ""))
	var operation_costs: Variant = workshop_combination.get("operationCostByOrderType", null)
	if not (operation_costs is Dictionary) or not operation_costs.has(order_type):
		return _failure("workshop combination must define operationCostByOrderType for " + order_type)
	var operations_per_cycle := float(operation_costs[order_type])
	if not workshop_combination.has("liquidHandlingOperationCost"):
		return _failure("workshop combination must define liquidHandlingOperationCost")
	var liquid_operation_cost := float(workshop_combination.get("liquidHandlingOperationCost", 0.0))
	if operations_per_cycle < 0.0 or liquid_operation_cost < 0.0:
		return _failure("workshop operation costs cannot be negative")
	var workshop_operations := operations_per_cycle + liquid_jar_count * liquid_operation_cost
	var production_pressure := 0.0
	for pressure in shape_pressure.values():
		production_pressure = maxf(production_pressure, float(pressure))
	return {
		"valid": true,
		"expectedBattleDurationLogicalMilli": expected_battle_duration_logical_milli,
		"expectedActivations": expected_activations,
		"effectiveShapeJarOutputRatesPerSecond": aggregate_rates,
		"shipStoneProgressRatesPerSecond": stone_rates,
		"shapeDemandPerActivation": shape_demand,
		"shapePressure": shape_pressure,
		"totalExpectedJarDemand": total_required_jars,
		"totalExpectedProductionCapacity": total_production_capacity,
		"productionPressure": production_pressure,
		"workshopOperationCount": workshop_operations,
		"liquidHandlingOperationCount": liquid_jar_count * liquid_operation_cost
	}

static func _failure(reason: String) -> Dictionary:
	return {"valid": false, "reason": reason}
