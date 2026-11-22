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
	var devices := [{"shapeProcessingRatePerSecond": {"small": 2.0}}]
	var ship_resources := {"expectedStoneProgressPerSecondByShape": {"small": 1.5, "large": 0.5}}
	var shape_progress := {"small": 1.0, "large": 1.0}
	var workshop := {
		"operationCostByOrderType": {"A": 1.0, "B": 3.0},
		"liquidHandlingOperationCost": 2.0
	}
	var result := SpaceSkillBuildContextEvaluator.evaluate(order, devices, workshop, ship_resources, shape_progress, 60000.0, profile)
	if not result.get("valid", false):
		return {"passed": false, "reason": result.get("reason", "unknown")}
	if not is_equal_approx(float(result.workshopOperationCount), 5.0):
		return {"passed": false, "reason": "workshop and liquid operation costs were not combined"}
	if not is_equal_approx(float(result.expectedActivations), 12.0):
		return {"passed": false, "reason": "expected activation count is incorrect"}
	var unsupported := SpaceSkillBuildContextEvaluator.evaluate(
		order, [{"shapeProcessingRatePerSecond": {"large": 1.0}}], workshop, ship_resources, shape_progress, 60000.0, profile)
	if unsupported.get("valid", false):
		return {"passed": false, "reason": "unsupported required shape must fail closed"}
	var bottleneck_order := order.duplicate(true)
	bottleneck_order["requirements"].append({"shape": "large"})
	var bottleneck := SpaceSkillBuildContextEvaluator.evaluate(
		bottleneck_order,
		[{"shapeJarRatePerSecond": {"small": 10.0, "large": 0.1}}],
		workshop,
		60000.0,
		profile
	)
	if not bottleneck.get("valid", false):
		return {"passed": false, "reason": bottleneck.get("reason", "bottleneck context failed")}
	if not is_equal_approx(float(bottleneck.productionPressure), float(bottleneck.shapePressure["large"])):
		return {"passed": false, "reason": "aggregate supply hid the limiting shape rate"}
	return {"passed": true, "productionPressure": result.productionPressure, "bottleneckPressure": bottleneck.productionPressure}
