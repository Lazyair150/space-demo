extends RefCounted
class_name SpaceBattleEconomyEvaluatorProbe
## Deterministic model probe. Uses explicit synthetic assumptions, not live balance data.

static func run() -> Dictionary:
	var battle := {"durationLogicalMilli": 60000}
	var resources := {
		"initialShapeJars": {"small": 4, "large": 0},
		"shapeJarOutputPerSecond": {"small": 0.1, "large": 0.02},
		"initialLiquids": {"water": 2},
		"liquidOutputPerSecond": {"water": 0.05},
		"liquidInventoryCapacity": 8,
		"workshopOperationsPerSecond": 0.2
	}
	var one_skill := [{
		"skillId": "shield",
		"area": "Passive",
		"cooldownDurationLogicalMilli": 10000,
		"jarOrder": {"type": "A", "requirements": [
			{"shape": "small", "liquid": "water", "liquidUnits": 2}
		]},
		"workshopOperationsPerActivation": 0.1
	}]
	var single := SpaceBattleEconomyEvaluator.evaluate(battle, resources, one_skill)
	if not bool(single.get("valid", false)):
		return {"passed": false, "reason": String(single.get("reason", "single skill invalid"))}
	var single_report: Dictionary = single.skills[0]
	if float(single_report.realizedActivations) >= float(single_report.requestedActivations):
		return {"passed": false, "reason": "liquid or workshop scarcity should constrain the skill"}

	var shared_skills := one_skill.duplicate(true)
	var second := one_skill[0].duplicate(true)
	second["skillId"] = "overdrive"
	second["jarOrder"] = {"type": "A", "requirements": [
		{"shape": "small", "liquid": "water", "liquidUnits": 1}
	]}
	shared_skills.append(second)
	var shared := SpaceBattleEconomyEvaluator.evaluate(battle, resources, shared_skills)
	if not bool(shared.get("valid", false)):
		return {"passed": false, "reason": String(shared.get("reason", "shared skills invalid"))}
	if float(shared.commonActivationFulfillment) >= float(single.commonActivationFulfillment):
		return {"passed": false, "reason": "adding a competing skill must not improve shared fulfillment"}

	var missing_units := one_skill.duplicate(true)
	missing_units[0].jarOrder.requirements[0].erase("liquidUnits")
	var rejected := SpaceBattleEconomyEvaluator.evaluate(battle, resources, missing_units)
	if bool(rejected.get("valid", false)):
		return {"passed": false, "reason": "liquid demand without explicit units must be rejected"}

	return {
		"passed": true,
		"singleSkillFulfillment": single.commonActivationFulfillment,
		"sharedSkillFulfillment": shared.commonActivationFulfillment,
		"bottlenecks": shared.bottlenecks
	}
