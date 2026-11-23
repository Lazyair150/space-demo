extends RefCounted
class_name SpaceSkillEffectValueProbe

static func run() -> Dictionary:
	var definition := BuffDefinition.new()
	definition.id = &"probe.effect"
	definition.definition_version = 3
	definition.duration = 6.0
	definition.tick_interval = 2.0
	definition.tick_damage = 4
	definition.max_stacks = 3
	definition.stack_policy = BuffDefinition.StackPolicy.ADD_STACK
	definition.balance_metrics = {"power": 12.0, "survivability": 2.0}
	var catalog := SpaceEffectCatalog.new()
	if not catalog.register_buff(definition):
		return {"passed": false, "reason": "valid versioned effect failed catalog registration"}
	var metrics := catalog.resolve_balance_metrics("probe.effect", 3)
	if not is_equal_approx(float(metrics.get("duration", -1.0)), 6.0):
		return {"passed": false, "reason": "duration was not derived from the effect"}
	if not is_equal_approx(float(metrics.get("periodic_damage", -1.0)), 12.0):
		return {"passed": false, "reason": "periodic damage was not derived from tick data"}
	if not is_equal_approx(float(metrics.get("stack_potential", -1.0)), 3.0):
		return {"passed": false, "reason": "stack potential was not derived from stack policy"}
	if not catalog.resolve_balance_metrics("probe.effect", 2).is_empty():
		return {"passed": false, "reason": "catalog silently substituted another effect version"}
	return {"passed": true, "metrics": metrics}
