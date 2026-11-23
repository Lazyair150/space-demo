extends RefCounted
class_name SpaceProgressionRuntimeProfileComposer
## Composes immutable definition data with one owned instance's growth values.
## Strict per-kind key allowlists prevent accidental cross-subsystem attribute leakage.

static func compose_ship(definition: SpaceShipDefinition, instance: SpaceOwnedProgressionInstance) -> Dictionary:
	if not _matches(definition, instance, "ship", String(definition.ship_id if definition != null else &""), definition.definition_version if definition != null else 0):
		return {}
	var growth := instance.growth_attributes
	if not _only_keys(growth, ["stoneProgressRateMultiplier"]):
		return {}
	var rates := definition.expected_stone_progress_per_second_by_shape.duplicate(true)
	var multiplier: Variant = growth.get("stoneProgressRateMultiplier", 1.0)
	if not _multiply_all(rates, multiplier):
		return {}
	return {
		"definitionId": String(definition.ship_id),
		"definitionVersion": definition.definition_version,
		"instance": instance.build_frozen_snapshot(),
		"shipResourceProfile": {"expectedStoneProgressPerSecondByShape": rates}
	}

static func compose_parser(definition: SpaceOreParserDefinition, instance: SpaceOwnedProgressionInstance, shapes: Array) -> Dictionary:
	if not _matches(definition, instance, "ore_parser", String(definition.parser_id if definition != null else &""), definition.definition_version if definition != null else 0):
		return {}
	if not definition.is_valid_for_shapes(shapes):
		return {}
	var growth := instance.growth_attributes
	if not _only_keys(growth, ["shapeProcessingRateMultiplier", "progressPerJarMultiplier", "productionPercentageBonus"]):
		return {}
	var profile := definition.build_runtime_profile()
	var rates: Dictionary = profile.shapeProcessingRatePerSecond
	var progress: Dictionary = profile.progressPerJarByShape
	if not _multiply_all(rates, growth.get("shapeProcessingRateMultiplier", 1.0)):
		return {}
	if not _multiply_all(progress, growth.get("progressPerJarMultiplier", 1.0)):
		return {}
	var bonus: Variant = growth.get("productionPercentageBonus", 0)
	if typeof(bonus) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(bonus)):
		return {}
	var percentage := float(profile.productionPercentage) + float(bonus)
	if percentage < 0.0 or percentage > 100.0:
		return {}
	profile.shapeProcessingRatePerSecond = rates
	profile.progressPerJarByShape = progress
	profile.productionPercentage = int(round(percentage))
	profile["ownedInstance"] = instance.build_frozen_snapshot()
	return profile

static func compose_device(definition: SpaceProductionDeviceDefinition, instance: SpaceOwnedProgressionInstance, slot_id: String) -> Dictionary:
	if not _matches(definition, instance, "production_device", String(definition.device_id if definition != null else &""), definition.definition_version if definition != null else 0):
		return {}
	var growth := instance.growth_attributes
	var profile := definition.runtime_profile.duplicate(true)
	if not _apply_flat_numeric_overlay(profile, growth, "runtimeAdd.", "runtimeMul."):
		return {}
	return {
		"slotId": slot_id,
		"deviceKind": definition.device_kind,
		"definitionId": String(definition.device_id),
		"definitionVersion": definition.definition_version,
		"deviceRuntimeProfile": profile,
		"ownedInstance": instance.build_frozen_snapshot()
	}

static func compose_workshop(definition: SpaceWorkshopDefinition, instance: SpaceOwnedProgressionInstance, shape_vocabulary: Array) -> Dictionary:
	if not _matches(definition, instance, "workshop", String(definition.workshop_id if definition != null else &""), definition.definition_version if definition != null else 0):
		return {}
	if not definition.get_validation_errors().is_empty():
		return {}
	for mark in definition.base_marks + definition.additional_marks:
		if not shape_vocabulary.has(mark):
			return {}
	var growth := instance.growth_attributes
	if not _only_workshop_keys(growth):
		return {}
	if not _is_integer_value(growth.get("maxJarsBonus", 0)) or not _is_integer_value(growth.get("maxLiquidsBonus", 0)) or not _is_integer_value(growth.get("liquidStagingCapacityBonus", 0)):
		return {}
	var max_jars := definition.max_jars + int(growth.get("maxJarsBonus", 0))
	var max_liquids := definition.max_liquids + int(growth.get("maxLiquidsBonus", 0))
	var staging := definition.liquid_staging_capacity
	if staging >= 0:
		staging += int(growth.get("liquidStagingCapacityBonus", 0))
	elif int(growth.get("liquidStagingCapacityBonus", 0)) != 0:
		return {} # Do not turn Core's documented fallback into an invented explicit capacity.
	if max_jars <= 0 or max_liquids <= 0 or staging < -1:
		return {}
	var marks: Array = definition.additional_marks.duplicate()
	for raw_key in growth:
		var attribute := String(raw_key)
		if not attribute.begins_with("additionalMark."):
			continue
		var key := attribute.trim_prefix("additionalMark.")
		var enabled: Variant = growth[raw_key]
		if not _is_integer_value(enabled) or int(enabled) not in [0, 1]:
			return {}
		if int(enabled) == 1:
			if key.is_empty() or not shape_vocabulary.has(key) or definition.base_marks.has(key) or marks.has(key):
				return {}
			marks.append(key)
	var result := {
		"name": definition.display_name,
		"baseMarks": definition.base_marks.duplicate(),
		"additionalMarks": marks,
		"ban": definition.banned_liquids.duplicate(),
		"maxJars": max_jars,
		"maxLiquids": max_liquids
	}
	if staging >= 0:
		result["liquidStagingCapacity"] = staging
	return result

static func compose_skill(definition: SpaceSkillDefinition, instance: SpaceOwnedProgressionInstance) -> SpaceSkillDefinition:
	if not _matches(definition, instance, "skill", String(definition.skill_id if definition != null else &""), definition.definition_version if definition != null else 0):
		return null
	var growth := instance.growth_attributes
	for raw_key in growth:
		var key := String(raw_key)
		if not (key.begins_with("effectAdd.") or key.begins_with("effectMul.") or key.begins_with("benefitAdd.") or key.begins_with("benefitMul.")):
			return null
	var result := definition.duplicate(true) as SpaceSkillDefinition
	var parameters := result.effect_parameters.duplicate(true)
	var effect_growth := _filter_prefixes(growth, ["effectAdd.", "effectMul."])
	if not _apply_flat_numeric_overlay(parameters, effect_growth, "effectAdd.", "effectMul."):
		return null
	result.effect_parameters = parameters
	return result

static func compose_skill_binding(binding: Dictionary, definition: SpaceSkillDefinition, instance: SpaceOwnedProgressionInstance, balance_profile: SpaceSkillBalanceProfile) -> Dictionary:
	var skill := compose_skill(definition, instance)
	if skill == null or balance_profile == null or not balance_profile.is_valid():
		return {}
	var result := binding.duplicate(true)
	var benefit: Variant = result.get("benefitProfile", null)
	var jar_order: Variant = result.get("jarOrder", null)
	var context: Variant = result.get("balanceContext", null)
	if not (benefit is Dictionary) or not (jar_order is Dictionary) or not (context is Dictionary):
		return {}
	var adjusted_benefit: Dictionary = benefit.duplicate(true)
	var additive_benefits := {}
	var multiplicative_benefits := {}
	for raw_key in instance.growth_attributes:
		var growth_key := String(raw_key)
		var prefix := ""
		var dimension := ""
		if growth_key.begins_with("effectAdd.") or growth_key.begins_with("effectMul."):
			prefix = "effectAdd." if growth_key.begins_with("effectAdd.") else "effectMul."
			var parameter_name := growth_key.trim_prefix(prefix)
			if not definition.effect_parameter_benefit_dimensions.has(parameter_name):
				return {} # Effect growth must explicitly declare its balance dimension.
			dimension = String(definition.effect_parameter_benefit_dimensions[parameter_name])
		elif growth_key.begins_with("benefitAdd.") or growth_key.begins_with("benefitMul."):
			prefix = "benefitAdd." if growth_key.begins_with("benefitAdd.") else "benefitMul."
			dimension = growth_key.trim_prefix(prefix)
		else:
			return {}
		var growth_value: Variant = instance.growth_attributes[raw_key]
		if dimension.is_empty() or not adjusted_benefit.has(dimension) or typeof(adjusted_benefit[dimension]) not in [TYPE_INT, TYPE_FLOAT]:
			return {}
		if typeof(growth_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(growth_value)):
			return {}
		if prefix == "effectAdd." or prefix == "benefitAdd.":
			additive_benefits[dimension] = float(additive_benefits.get(dimension, 0.0)) + float(growth_value)
		else:
			multiplicative_benefits[dimension] = float(multiplicative_benefits.get(dimension, 1.0)) * float(growth_value)
	for dimension in additive_benefits:
		adjusted_benefit[dimension] = float(adjusted_benefit[dimension]) + float(additive_benefits[dimension])
	for dimension in multiplicative_benefits:
		adjusted_benefit[dimension] = float(adjusted_benefit[dimension]) * float(multiplicative_benefits[dimension])
		if not is_finite(float(adjusted_benefit[dimension])) or float(adjusted_benefit[dimension]) < 0.0:
			return {}
	for dimension in additive_benefits:
		if not is_finite(float(adjusted_benefit[dimension])) or float(adjusted_benefit[dimension]) < 0.0:
			return {}
	var report := SpaceSkillBalanceModel.evaluate(adjusted_benefit, jar_order, context, balance_profile)
	if not bool(report.get("valid", false)) or String(report.get("balanceStatus", "")) == "undercosted":
		return {} # Growth may not increase skill benefit beyond its authored Jar cost curve.
	result["benefitProfile"] = adjusted_benefit
	result["balanceReport"] = report
	result["effectBinding"] = result.get("effectBinding", {}).duplicate(true)
	result["effectBinding"]["effectParameters"] = skill.effect_parameters.duplicate(true)
	return result

static func _filter_prefixes(source: Dictionary, prefixes: Array) -> Dictionary:
	var result := {}
	for key in source:
		for prefix in prefixes:
			if String(key).begins_with(String(prefix)):
				result[key] = source[key]
				break
	return result

static func _matches(definition: Resource, instance: SpaceOwnedProgressionInstance, kind: String, definition_id: String, version: int) -> bool:
	return definition != null and instance != null and instance.item_kind == kind and String(instance.definition_id) == definition_id and instance.definition_version == version and instance.get_validation_errors().is_empty()

static func _only_keys(source: Dictionary, allowed: Array) -> bool:
	for key in source:
		if not allowed.has(String(key)):
			return false
	return true

static func _multiply_all(values: Dictionary, raw_factor: Variant) -> bool:
	if typeof(raw_factor) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw_factor)) or float(raw_factor) < 0.0:
		return false
	for key in values:
		var adjusted := float(values[key]) * float(raw_factor)
		if not is_finite(adjusted) or adjusted < 0.0 or adjusted > 1000000000.0:
			return false
		values[key] = adjusted
	return true

static func _apply_shape_multipliers(values: Dictionary, multipliers: Variant) -> bool:
	if not (multipliers is Dictionary):
		return false
	for shape in multipliers:
		var key := String(shape)
		var factor: Variant = multipliers[shape]
		if not values.has(key) or typeof(factor) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(factor)) or float(factor) < 0.0:
			return false
		var adjusted := float(values[key]) * float(factor)
		if not is_finite(adjusted) or adjusted < 0.0 or adjusted > 1000000000.0:
			return false
		values[key] = adjusted
	return true

static func _apply_numeric_overlay(target: Dictionary, additions: Variant, multipliers: Variant) -> bool:
	if not (additions is Dictionary) or not (multipliers is Dictionary):
		return false
	for key in additions:
		var value: Variant = additions[key]
		if not target.has(key) or typeof(target[key]) not in [TYPE_INT, TYPE_FLOAT] or typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return false
		target[key] = float(target[key]) + float(value)
		if not is_finite(float(target[key])):
			return false
	for key in multipliers:
		var factor: Variant = multipliers[key]
		if not target.has(key) or typeof(target[key]) not in [TYPE_INT, TYPE_FLOAT] or typeof(factor) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(factor)) or float(factor) < 0.0:
			return false
		target[key] = float(target[key]) * float(factor)
		if not is_finite(float(target[key])):
			return false
	return true

static func _apply_flat_numeric_overlay(target: Dictionary, growth: Dictionary, addition_prefix: String, multiplier_prefix: String) -> bool:
	for raw_key in growth:
		var key := String(raw_key)
		var prefix := addition_prefix if key.begins_with(addition_prefix) else multiplier_prefix if key.begins_with(multiplier_prefix) else ""
		if prefix.is_empty():
			return false
		var field := key.trim_prefix(prefix)
		var value: Variant = growth[raw_key]
		if field.is_empty() or not target.has(field) or typeof(target[field]) not in [TYPE_INT, TYPE_FLOAT] or typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return false
		target[field] = float(target[field]) + float(value) if prefix == addition_prefix else float(target[field]) * float(value)
		if not is_finite(float(target[field])):
			return false
	return true

static func _only_workshop_keys(growth: Dictionary) -> bool:
	for raw_key in growth:
		var key := String(raw_key)
		if ["maxJarsBonus", "maxLiquidsBonus", "liquidStagingCapacityBonus"].has(key):
			continue
		if key.begins_with("additionalMark.") and not key.trim_prefix("additionalMark.").is_empty():
			continue
		return false
	return true

static func _is_integer_value(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(float(value)) and is_equal_approx(float(value), roundf(float(value))))
