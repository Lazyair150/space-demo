extends RefCounted
class_name SpaceOreParserRuleProfile
## Executes the deliberately narrow Parser-local contribution contract.
## These modifiers are applied to Space's frozen parser rates/thresholds; they are
## never serialized into Jar Core's workshop RuleContext.

const MAX_FIXED_POINT_UNITS: float = 1000000000.0
const MICRO: float = 1000000.0

static func compose(
	base_profile: Dictionary,
	definitions: Array[SpaceRuleContributionDefinition],
	instance: SpaceOwnedProgressionInstance,
	slot_id: String,
	shape_names: Array
) -> Dictionary:
	if base_profile.is_empty() or instance == null or slot_id.strip_edges().is_empty():
		return {}
	var rates: Variant = base_profile.get("shapeProcessingRatePerSecond", null)
	var thresholds: Variant = base_profile.get("progressPerJarByShape", null)
	if not (rates is Dictionary) or not (thresholds is Dictionary):
		return {}
	if rates.size() != shape_names.size() or thresholds.size() != shape_names.size():
		return {}
	var base_rates := rates.duplicate(true)
	var base_thresholds := thresholds.duplicate(true)
	for shape_value in shape_names:
		var shape := String(shape_value)
		if not rates.has(shape) or not thresholds.has(shape):
			return {}

	var resolved: Array[Dictionary] = []
	var seen_rules := {}
	for definition in definitions:
		if definition == null or not definition.get_validation_errors().is_empty():
			return {}
		if String(definition.scope) != "parser":
			return {}
		var contribution := definition.resolve(instance, slot_id)
		if contribution.is_empty():
			return {}
		var rule_identity := String(contribution.get("ruleId", "")) + "@" + str(int(contribution.get("ruleVersion", 0)))
		if rule_identity.is_empty() or seen_rules.has(rule_identity):
			return {}
		seen_rules[rule_identity] = true
		var effect := String(contribution.get("effect", ""))
		var target := String(contribution.get("target", ""))
		var expected_target := "shape_processing_rate" if effect == "ModifyIntensity" else ("progress_per_jar" if effect == "RetimeProcess" else "")
		if expected_target.is_empty() or target != expected_target:
			return {}
		var parameters: Variant = contribution.get("parameters", null)
		if not (parameters is Dictionary) or parameters.size() != 2 or not parameters.has("shape") or not parameters.has("multiplier"):
			return {}
		var shape := String(parameters.get("shape", ""))
		var multiplier_text := String(parameters.get("multiplier", ""))
		if not shape_names.has(shape) or not multiplier_text.is_valid_float():
			return {}
		var multiplier := multiplier_text.to_float()
		if not is_finite(multiplier) or multiplier <= 0.0 or multiplier > MAX_FIXED_POINT_UNITS:
			return {}
		contribution["resolvedShape"] = shape
		contribution["resolvedMultiplier"] = multiplier
		resolved.append(contribution)

	resolved.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_key := "%010d|%s|%s" % [int(a.get("priority", 0)), String(a.get("ruleId", "")), String(a.get("target", ""))]
		var b_key := "%010d|%s|%s" % [int(b.get("priority", 0)), String(b.get("ruleId", "")), String(b.get("target", ""))]
		return a_key < b_key
	)
	for contribution in resolved:
		var shape := String(contribution.get("resolvedShape", ""))
		var multiplier := float(contribution.get("resolvedMultiplier", 0.0))
		var effect := String(contribution.get("effect", ""))
		var target_map: Dictionary = rates if effect == "ModifyIntensity" else thresholds
		var adjusted := float(target_map[shape]) * multiplier
		if not is_finite(adjusted) or adjusted < 0.0 or adjusted > MAX_FIXED_POINT_UNITS:
			return {}
		if effect == "RetimeProcess" and (adjusted <= 0.0 or round(adjusted * MICRO) < 1.0):
			return {}
		target_map[shape] = adjusted

	var clean_contributions: Array[Dictionary] = []
	for contribution in resolved:
		var clean := contribution.duplicate(true)
		clean.erase("resolvedShape")
		clean.erase("resolvedMultiplier")
		clean_contributions.append(clean)
	var payload := {
		"schemaVersion": 1,
		"parserDefinitionId": String(base_profile.get("parserId", "")),
		"parserDefinitionVersion": int(base_profile.get("definitionVersion", 0)),
		"slotId": slot_id,
		"ownedInstanceId": String(instance.instance_id),
		"progressionRevision": instance.progression_revision,
		"baseShapeProcessingRatePerSecond": base_rates,
		"baseProgressPerJarByShape": base_thresholds,
		"contributions": clean_contributions
	}
	payload["fingerprint"] = _fingerprint(payload)
	if String(payload.fingerprint).is_empty():
		return {}
	var result := base_profile.duplicate(true)
	result["shapeProcessingRatePerSecond"] = rates
	result["progressPerJarByShape"] = thresholds
	result["parserRuleProfile"] = payload
	return result

static func _fingerprint(value: Dictionary) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update(JSON.stringify(_canonicalize(value)).to_utf8_buffer())
	return hashing.finish().hex_encode()

static func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
		var result := {}
		for key in keys:
			result[key] = _canonicalize(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_canonicalize(item))
		return result
	return value
