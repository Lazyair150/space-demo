extends RefCounted
class_name SpaceSkillBuildContextEvaluator
## Converts the selected production-device/workshop build into measurable per-skill pressure.
## Expected schema:
## ship_resource_profile.expectedStoneProgressPerSecondByShape: { shape_id: non-negative progress/second }
## device.shapeProcessingRatePerSecond: { shape_id: positive progress/second }
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
	for raw_device in production_devices:
		if not (raw_device is Dictionary):
			return _failure("production device selection must be a dictionary")
		var rates: Variant = raw_device.get("shapeProcessingRatePerSecond", null)
		if not (rates is Dictionary) or rates.is_empty():
			return _failure("production device must provide shapeProcessingRatePerSecond")
		for shape in rates:
			var rate := float(rates[shape])
			if rate < 0.0:
				return _failure("shape production rates cannot be negative")
			aggregate_rates[String(shape)] = float(aggregate_rates.get(String(shape), 0.0)) + rate

	var stone_rates: Variant = ship_resource_profile.get("expectedStoneProgressPerSecondByShape", null)
	if not (stone_rates is Dictionary) or stone_rates.is_empty():
		return _failure("ship resource profile must provide expectedStoneProgressPerSecondByShape")
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

	var expected_activations := expected_battle_duration_logical_milli / maxf(
		float(jar_order.get("cooldownDurationLogicalMilli", 0)),
		profile.cooldown_floor_logical_milli
	)
	var battle_seconds := expected_battle_duration_logical_milli / 1000.0
	var total_required_jars := 0.0
	var total_production_capacity := 0.0
	var shape_pressure := {}
	for shape in shape_demand:
		var processor_rate := float(aggregate_rates.get(shape, 0.0))
		var stone_rate := float(stone_rates.get(shape, 0.0))
		var progress_per_jar := float(shape_progress_per_jar.get(shape, 0.0))
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
