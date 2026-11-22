extends RefCounted
class_name SpaceJarRequirementCostAdapter
## Separates Jar's qualitative requirement contract from Space's quantitative economy forecast.
## Jar Requirement contains shape and optional target liquid only. Numeric external liquid
## demand is supplied by a named forecast scenario or a resolved execution-plan projection.

static func normalize(jar_order: Dictionary, forecast: Variant) -> Dictionary:
	var requirements: Variant = jar_order.get("requirements", null)
	if not (requirements is Array) or requirements.is_empty():
		return _failure("Jar requirements must be a non-empty array")
	var shape_cost := {}
	var required_liquids := {}
	for raw in requirements:
		if not (raw is Dictionary):
			return _failure("Jar requirement entry must be a dictionary")
		var requirement: Dictionary = raw
		var shape := String(requirement.get("shape", "")).strip_edges()
		if shape.is_empty():
			return _failure("Jar requirement shape is required")
		shape_cost[shape] = int(shape_cost.get(shape, 0)) + 1
		var liquid := String(requirement.get("liquid", "")).strip_edges()
		if not liquid.is_empty():
			required_liquids[liquid] = true
	if required_liquids.is_empty() and (forecast == null or (forecast is Dictionary and forecast.is_empty())):
		return {
			"valid": true,
			"shapeJarsPerActivation": shape_cost,
			"liquidUnitsPerActivation": {},
			"liquidBearingRequirementCount": 0,
			"forecastSource": "not_applicable_no_liquid_requirement"
		}
	if not (forecast is Dictionary):
		return _failure("resourceCostForecast must be a dictionary separate from jarOrder")
	var source := String(forecast.get("forecastSource", "")).strip_edges()
	if source.is_empty():
		return _failure("forecastSource is required to identify the estimate basis")
	var raw_liquid_cost: Variant = forecast.get("liquidUnitsPerActivation", null)
	if not (raw_liquid_cost is Dictionary):
		return _failure("liquidUnitsPerActivation must be a dictionary")
	var liquid_cost := {}
	for liquid in required_liquids:
		if not raw_liquid_cost.has(liquid):
			return _failure("forecast is missing external liquid estimate for " + String(liquid))
	for liquid in raw_liquid_cost:
		var key := String(liquid).strip_edges()
		var raw_units: Variant = raw_liquid_cost[liquid]
		if typeof(raw_units) != TYPE_INT and typeof(raw_units) != TYPE_FLOAT:
			return _failure("liquid forecast units must be numeric: " + key)
		var units := float(raw_units)
		if not required_liquids.has(key):
			return _failure("forecast contains a liquid not requested by this Jar order: " + key)
		if units < 0.0 or not is_finite(units) or floor(units) != units:
			return _failure("liquid forecast units must be finite non-negative whole units: " + key)
		liquid_cost[key] = units
	return {
		"valid": true,
		"shapeJarsPerActivation": shape_cost,
		"liquidUnitsPerActivation": liquid_cost,
		"liquidBearingRequirementCount": required_liquids.size(),
		"forecastSource": source
	}

static func _failure(reason: String) -> Dictionary:
	return {"valid": false, "reason": reason}
