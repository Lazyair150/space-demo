extends RefCounted
class_name SpaceSkillBalanceModelProbe
## Lightweight deterministic probe for the benefit/cost bridge.

static func run() -> Dictionary:
	var profile := SpaceSkillBalanceProfile.new()
	var benefit := {
		"power": 20.0,
		"duration": 10.0,
		"coverage": 1.0,
		"control": 0.0,
		"survivability": 0.0,
		"utility": 0.0
	}
	var simple_order := {
		"type": "A",
		"cooldownDurationLogicalMilli": 10000,
		"requirements": [
			{"shape": "small"},
			{"shape": "small"}
		]
	}
	var liquid_order := {
		"type": "A",
		"requirements": [
			{"shape": "small", "liquid": "water"},
			{"shape": "small", "liquid": "water"}
		]
	}
	var simple := SpaceSkillBalanceModel.evaluate(benefit, simple_order, {}, profile)
	var liquid := SpaceSkillBalanceModel.evaluate(benefit, liquid_order, {}, profile)
	if not simple.get("valid", false) or not liquid.get("valid", false):
		return {"passed": false, "reason": "valid baseline recipes were rejected"}
	if float(liquid.actualDifficulty) <= float(simple.actualDifficulty):
		return {"passed": false, "reason": "liquid-bearing jars must increase difficulty"}
	var stronger_benefit := benefit.duplicate(true)
	stronger_benefit["power"] = 40.0
	var stronger := SpaceSkillBalanceModel.evaluate(stronger_benefit, liquid_order, {}, profile)
	if float(stronger.targetDifficulty) <= float(liquid.targetDifficulty):
		return {"passed": false, "reason": "stronger benefit must raise target difficulty"}
	var fast_order := liquid_order.duplicate(true)
	fast_order["cooldownDurationLogicalMilli"] = 2000
	var fast := SpaceSkillBalanceModel.evaluate(benefit, fast_order, {}, profile)
	if float(fast.targetDifficulty) <= float(liquid.targetDifficulty):
		return {"passed": false, "reason": "shorter cooldown must raise sustained benefit target"}
	var more_complex := liquid_order.duplicate(true)
	more_complex["requirements"].append({"shape": "large", "liquid": "oil"})
	var complex_result := SpaceSkillBalanceModel.evaluate(benefit, more_complex, {}, profile)
	if float(complex_result.actualDifficulty) <= float(liquid.actualDifficulty):
		return {"passed": false, "reason": "more complex liquid/shape requirements must increase difficulty"}
	return {
		"passed": true,
		"simpleDifficulty": simple.actualDifficulty,
		"liquidDifficulty": liquid.actualDifficulty,
		"benefitTargetDifficulty": liquid.targetDifficulty,
		"complexDifficulty": complex_result.actualDifficulty
	}
