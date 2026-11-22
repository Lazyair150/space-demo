extends RefCounted
class_name SpaceSkillBuildContextProbe

static func run() -> Dictionary:
	var profile := SpaceSkillBalanceProfile.new()
	var order := {
		"type": "B",
		"cooldownDurationLogicalMilli": 5000,
		"requirements": [
			{"shape": "small"},
			{"shape": "small", "liquid": "water"}
		]
	}
	var devices := [{"shapeJarRatePerSecond": {"small": 2.0}}]
	var workshop := {
		"operationCostByOrderType": {"A": 1.0, "B": 3.0},
		"liquidHandlingOperationCost": 2.0
	}
	var result := SpaceSkillBuildContextEvaluator.evaluate(order, devices, workshop, 60000.0, profile)
	if not result.get("valid", false):
		return {"passed": false, "reason": result.get("reason", "unknown")}
	if not is_equal_approx(float(result.workshopOperationCount), 5.0):
		return {"passed": false, "reason": "workshop and liquid operation costs were not combined"}
	if not is_equal_approx(float(result.expectedActivations), 12.0):
		return {"passed": false, "reason": "expected activation count is incorrect"}
	var unsupported := SpaceSkillBuildContextEvaluator.evaluate(
		order, [{"shapeJarRatePerSecond": {"large": 1.0}}], workshop, 60000.0, profile)
	if unsupported.get("valid", false):
		return {"passed": false, "reason": "unsupported required shape must fail closed"}
	return {"passed": true, "productionPressure": result.productionPressure}
