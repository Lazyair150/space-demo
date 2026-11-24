extends RefCounted
class_name SpaceSkillBuildContextEvaluatorProbe
## Synthetic checks for the pre-battle parser percentage as a parser-owned throughput attribute.

static func run() -> Dictionary:
	var profile := SpaceSkillBalanceProfile.new()
	var order := {
		"type": "A",
		"cooldownDurationLogicalMilli": 10000,
		"requirements": [{"shape": "圆罐"}]
	}
	var workshop := {
		"operationCostByOrderType": {"A": 1.0},
		"liquidHandlingOperationCost": 0.0
	}
	var ship_resources := {
		"expectedStoneProgressPerSecondByShape": {
			"圆罐": 10.0,
			"方罐": 10.0
		}
	}
	var parser_profile := {
		"parserId": "probe-parser",
		"definitionVersion": 1,
		"productionPercentage": 50,
		"shapeProcessingRatePerSecond": {
			"圆罐": 4.0,
			"方罐": 8.0
		},
		"progressPerJarByShape": {
			"圆罐": 2.0,
			"方罐": 2.0
		}
	}
	var devices := [{
		"slotId": "parser-slot",
		"deviceKind": "ore_parser",
		"definitionId": "probe-parser",
		"definitionVersion": 1,
		"oreParserProfile": parser_profile
	}]
	var fifty := SpaceSkillBuildContextEvaluator.evaluate(
		order, devices, workshop, ship_resources,
		parser_profile.progressPerJarByShape, 10000.0, profile
	)
	if not bool(fifty.get("valid", false)):
		return _failure("50% parser profile was rejected: " + String(fifty.get("reason", "")))
	var fifty_rate := float(fifty.effectiveShapeJarOutputRatesPerSecond.get("圆罐", 0.0))
	if absf(fifty_rate - 1.0) > 0.000001:
		return _failure("50% parser attribute did not halve its own throughput")
	# Adding another shape does not divide or steal the selected shape's output share.
	if absf(float(fifty.effectiveShapeJarOutputRatesPerSecond.get("方罐", 0.0)) - 2.0) > 0.000001:
		return _failure("parser percentage was treated as a cross-shape allocation")

	var full_profile := parser_profile.duplicate(true)
	full_profile.productionPercentage = 100
	var full_devices := devices.duplicate(true)
	full_devices[0].oreParserProfile = full_profile
	var full := SpaceSkillBuildContextEvaluator.evaluate(
		order, full_devices, workshop, ship_resources,
		full_profile.progressPerJarByShape, 10000.0, profile
	)
	if not bool(full.get("valid", false)):
		return _failure("100% parser profile was rejected")
	if absf(float(full.effectiveShapeJarOutputRatesPerSecond.get("圆罐", 0.0)) - 2.0) > 0.000001:
		return _failure("100% parser attribute did not restore full configured throughput")

	# The ship's expected stone profile and the universal parser must use the exact
	# same shape vocabulary; silent zero-rate fallbacks hide broken pre-battle builds.
	var incomplete_ship_resources := ship_resources.duplicate(true)
	incomplete_ship_resources.expectedStoneProgressPerSecondByShape.erase("方罐")
	var incomplete := SpaceSkillBuildContextEvaluator.evaluate(
		order, devices, workshop, incomplete_ship_resources,
		parser_profile.progressPerJarByShape, 10000.0, profile
	)
	if bool(incomplete.get("valid", false)):
		return _failure("build context accepted incomplete ship/parser shape coverage")

	var sub_precision_parser := parser_profile.duplicate(true)
	sub_precision_parser.progressPerJarByShape["圆罐"] = 0.0000001
	var sub_precision_devices := devices.duplicate(true)
	sub_precision_devices[0].oreParserProfile = sub_precision_parser
	var sub_precision := SpaceSkillBuildContextEvaluator.evaluate(
		order, sub_precision_devices, workshop, ship_resources,
		sub_precision_parser.progressPerJarByShape, 10000.0, profile
	)
	if bool(sub_precision.get("valid", false)):
		return _failure("build context accepted a progress threshold below fixed-point precision")

	var missing_thresholds := SpaceSkillBuildContextEvaluator.evaluate(
		order, devices, workshop, ship_resources, {}, 10000.0, profile
	)
	if bool(missing_thresholds.get("valid", false)):
		return _failure("build context accepted a threshold map that omitted the frozen parser's thresholds")
	var mismatched_thresholds: Dictionary = parser_profile.progressPerJarByShape.duplicate(true)
	mismatched_thresholds["圆罐"] = 3.0
	var mismatched := SpaceSkillBuildContextEvaluator.evaluate(
		order, devices, workshop, ship_resources, mismatched_thresholds, 10000.0, profile
	)
	if bool(mismatched.get("valid", false)):
		return _failure("build context accepted thresholds that differed from the frozen parser profile")

	return {
		"passed": true,
		"halfPercentShapeRate": fifty_rate,
		"fullPercentShapeRate": full.effectiveShapeJarOutputRatesPerSecond["圆罐"]
	}

static func _failure(reason: String) -> Dictionary:
	return {"passed": false, "reason": reason}
