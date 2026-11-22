extends RefCounted
class_name SpaceBattleEconomyEvaluator
## Evaluates all equipped skills against one shared battle-time resource budget.
## This is a planning/forecast model, not a replacement for Jar's authoritative runtime ledger.
##
## Input contract:
## battle:
##   durationLogicalMilli: positive simulation duration
## resources:
##   initialShapeJars: { shape_id: non-negative whole jars }
##   shapeJarOutputPerSecond: { shape_id: non-negative jars/second }
##   initialLiquids: { liquid_id: non-negative units }
##   liquidOutputPerSecond: { liquid_id: non-negative units/second }
##   liquidInventoryCapacity: non-negative total units; -1 means unbounded/unknown
##   workshopOperationsPerSecond: non-negative operations/second
## skills: array of { skillId, area: Active|Passive, cooldownDurationLogicalMilli,
##   jarOrder: { type, requirements:[{shape, liquid?, liquidUnits?}] },
##   workshopOperationsPerActivation, requestedActivations? }
##
## For Active skills, requestedActivations is an explicit player-planning assumption.
## For Passive skills, requestedActivations is an explicit trigger forecast. If omitted,
## the cooldown ceiling is used. This avoids pretending trigger policy is already implemented.
##
## Liquid units are intentionally explicit. A liquid-bearing Jar without liquidUnits is
## rejected: the evaluator must not invent the amount from the fact that a Jar has liquid.

static func evaluate(battle: Dictionary, resources: Dictionary, skills: Array) -> Dictionary:
	var duration_milli := float(battle.get("durationLogicalMilli", 0.0))
	if duration_milli <= 0.0:
		return _failure("battle durationLogicalMilli must be positive")
	if skills.is_empty():
		return _failure("at least one equipped skill is required")
	var duration_seconds := duration_milli / 1000.0
	var shape_budget := _build_budget(
		resources.get("initialShapeJars", {}),
		resources.get("shapeJarOutputPerSecond", {}),
		duration_seconds,
		true
	)
	if not shape_budget.valid:
		return _failure("invalid shape resource budget: " + shape_budget.reason)
	var liquid_budget := _build_budget(
		resources.get("initialLiquids", {}),
		resources.get("liquidOutputPerSecond", {}),
		duration_seconds,
		true
	)
	if not liquid_budget.valid:
		return _failure("invalid liquid resource budget: " + liquid_budget.reason)

	var capacity := float(resources.get("liquidInventoryCapacity", -1.0))
	if capacity < -1.0:
		return _failure("liquidInventoryCapacity must be -1 or non-negative")
	# Capacity constrains instantaneous stock, not cumulative lifetime throughput.
	# Consumption frees room for later production; without a time-resolved trigger schedule,
	# cumulative supply remains an upper-bound forecast and capacity is reported separately.
	var liquid_storage_limited := false
	if capacity >= 0.0:
		var initial_liquid_total := 0.0
		for amount in resources.get("initialLiquids", {}).values():
			initial_liquid_total += float(amount)
		liquid_storage_limited = initial_liquid_total > capacity

	var workshop_rate := float(resources.get("workshopOperationsPerSecond", -1.0))
	if workshop_rate < 0.0:
		return _failure("workshopOperationsPerSecond must be provided and non-negative")
	var workshop_budget := workshop_rate * duration_seconds

	var demands: Array[Dictionary] = []
	for raw_skill in skills:
		if not (raw_skill is Dictionary):
			return _failure("skill entry must be a dictionary")
		var skill: Dictionary = raw_skill
		var skill_id := String(skill.get("skillId", "")).strip_edges()
		if skill_id.is_empty():
			return _failure("skillId is required")
		var area := String(skill.get("area", ""))
		if not ["Active", "Passive"].has(area):
			return _failure("skill area must be Active or Passive: " + skill_id)
		var cooldown := float(skill.get("cooldownDurationLogicalMilli", -1.0))
		if cooldown <= 0.0:
			return _failure("skill cooldown must be positive: " + skill_id)
		var order: Variant = skill.get("jarOrder", null)
		if not (order is Dictionary):
			return _failure("skill jarOrder must be a dictionary: " + skill_id)
		var requirements: Variant = order.get("requirements", null)
		if not (requirements is Array) or requirements.is_empty():
			return _failure("skill Jar requirements must be non-empty: " + skill_id)
		var shape_cost := {}
		var liquid_cost := {}
		for raw_requirement in requirements:
			if not (raw_requirement is Dictionary):
				return _failure("Jar requirement must be a dictionary: " + skill_id)
			var requirement: Dictionary = raw_requirement
			var shape := String(requirement.get("shape", "")).strip_edges()
			if shape.is_empty():
				return _failure("Jar requirement shape missing: " + skill_id)
			shape_cost[shape] = float(shape_cost.get(shape, 0.0)) + 1.0
			var liquid := String(requirement.get("liquid", "")).strip_edges()
			if not liquid.is_empty():
				if not requirement.has("liquidUnits"):
					return _failure("liquidUnits must be explicit for " + skill_id + " / " + liquid)
				var units := float(requirement.get("liquidUnits", -1.0))
				if units <= 0.0:
					return _failure("liquidUnits must be positive for " + skill_id + " / " + liquid)
				liquid_cost[liquid] = float(liquid_cost.get(liquid, 0.0)) + units
		var cooldown_ceiling := 1 + int(floor(maxf(0.0, duration_milli - 0.001) / cooldown))
		if area == "Active" and not skill.has("requestedActivations"):
			return _failure("Active skill requires an explicit requestedActivations planning assumption: " + skill_id)
		var requested := int(skill.get("requestedActivations", cooldown_ceiling))
		if requested < 0:
			return _failure("requestedActivations cannot be negative: " + skill_id)
		var desired := mini(requested, cooldown_ceiling)
		var operations := float(skill.get("workshopOperationsPerActivation", 0.0))
		if operations < 0.0:
			return _failure("workshopOperationsPerActivation cannot be negative: " + skill_id)
		demands.append({
			"skillId": skill_id,
			"area": area,
			"desiredActivations": desired,
			"shapeCostPerActivation": shape_cost,
			"liquidCostPerActivation": liquid_cost,
			"workshopCostPerActivation": operations
		})

	# Deterministic proportional rationing: every skill gets the same activation fraction
	# until one shared resource becomes the bottleneck. No hidden priority by array order.
	var common_fraction := 1.0
	for demand in demands:
		var desired := float(demand.desiredActivations)
		if desired <= 0.0:
			continue
		for shape in demand.shapeCostPerActivation:
			var total_demand := 0.0
			for other in demands:
				total_demand += float(other.desiredActivations) * float(other.shapeCostPerActivation.get(shape, 0.0))
			if total_demand > 0.0:
				common_fraction = minf(common_fraction, float(shape_budget.supply.get(shape, 0.0)) / total_demand)
		for liquid in demand.liquidCostPerActivation:
			var total_demand := 0.0
			for other in demands:
				total_demand += float(other.desiredActivations) * float(other.liquidCostPerActivation.get(liquid, 0.0))
			if total_demand > 0.0:
				common_fraction = minf(common_fraction, float(liquid_budget.supply.get(liquid, 0.0)) / total_demand)
	var total_workshop_demand := 0.0
	for demand in demands:
		total_workshop_demand += float(demand.desiredActivations) * float(demand.workshopCostPerActivation)
	if total_workshop_demand > 0.0:
		common_fraction = minf(common_fraction, workshop_budget / total_workshop_demand)
	common_fraction = clampf(common_fraction, 0.0, 1.0)

	var skill_reports: Array[Dictionary] = []
	var total_requested := 0.0
	var total_realized := 0.0
	var total_workshop_used := 0.0
	var shape_used := {}
	var liquid_used := {}
	for demand in demands:
		var requested := float(demand.desiredActivations)
		var realized := requested * common_fraction
		total_requested += requested
		total_realized += realized
		var per_skill_shape_used := {}
		for shape in demand.shapeCostPerActivation:
			var used := realized * float(demand.shapeCostPerActivation[shape])
			shape_used[shape] = float(shape_used.get(shape, 0.0)) + used
			per_skill_shape_used[shape] = used
		var per_skill_liquid_used := {}
		for liquid in demand.liquidCostPerActivation:
			var used := realized * float(demand.liquidCostPerActivation[liquid])
			liquid_used[liquid] = float(liquid_used.get(liquid, 0.0)) + used
			per_skill_liquid_used[liquid] = used
		var operations_used := realized * float(demand.workshopCostPerActivation)
		total_workshop_used += operations_used
		skill_reports.append({
			"skillId": demand.skillId,
			"area": demand.area,
			"requestedActivations": requested,
			"realizedActivations": realized,
			"activationFulfillment": common_fraction,
			"shapeResourceUse": per_skill_shape_used,
			"liquidResourceUse": per_skill_liquid_used,
			"workshopOperationsUsed": operations_used
		})

	var bottlenecks: Array[String] = []
	if common_fraction < 0.999999:
		for shape in shape_used:
			if float(shape_budget.supply.get(shape, 0.0)) <= float(shape_used[shape]) + 0.000001:
				bottlenecks.append("shape:" + String(shape))
		for liquid in liquid_used:
			if float(liquid_budget.supply.get(liquid, 0.0)) <= float(liquid_used[liquid]) + 0.000001:
				bottlenecks.append("liquid:" + String(liquid))
		if workshop_budget <= total_workshop_used + 0.000001:
			bottlenecks.append("workshop_operations")
	return {
		"valid": true,
		"battleDurationLogicalMilli": duration_milli,
		"commonActivationFulfillment": common_fraction,
		"totalRequestedActivations": total_requested,
		"totalRealizedActivations": total_realized,
		"totalTheoreticalSkillActivations": total_requested,
		"totalRealizedSkillActivations": total_realized,
		"liquidStorageCapacity": capacity,
		"liquidStorageInitialOverflowRisk": liquid_storage_limited,
		"resourceBudget": {
			"shapeSupply": shape_budget.supply,
			"shapeUse": shape_used,
			"liquidSupply": liquid_budget.supply,
			"liquidUse": liquid_used,
			"workshopOperationsSupply": workshop_budget,
			"workshopOperationsUse": total_workshop_used
		},
		"bottlenecks": bottlenecks,
		"skills": skill_reports
	}

static func _build_budget(initial_value: Variant, rate_value: Variant, duration_seconds: float, integer_units: bool) -> Dictionary:
	if not (initial_value is Dictionary) or not (rate_value is Dictionary):
		return {"valid": false, "reason": "initial stock and output rate must be dictionaries"}
	var supply := {}
	var keys := {}
	for key in initial_value:
		keys[String(key)] = true
	for key in rate_value:
		keys[String(key)] = true
	var total := 0.0
	for key in keys:
		var initial := float(initial_value.get(key, 0.0))
		var rate := float(rate_value.get(key, 0.0))
		if initial < 0.0 or rate < 0.0:
			return {"valid": false, "reason": "resource stock and rates cannot be negative"}
		var amount := initial + rate * duration_seconds
		if integer_units:
			amount = floor(amount)
		supply[key] = amount
		total += amount
	return {"valid": true, "supply": supply, "total_supply": total}

static func _failure(reason: String) -> Dictionary:
	return {"valid": false, "reason": reason}
