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
		"maxLiquids": max_liquids,
		"ownedInstance": instance.build_frozen_snapshot()
	}
	if staging >= 0:
		result["liquidStagingCapacity"] = staging
	return result

static func compose_skill(definition: SpaceSkillDefinition, instance: SpaceOwnedProgressionInstance) -> SpaceSkillDefinition:
	if not _matches(definition, instance, "skill", String(definition.skill_id if definition != null else &""), definition.definition_version if definition != null else 0):
		return null
	var growth := instance.growth_attributes
		var result := definition.duplicate(true) as SpaceSkillDefinition
	var parameters := result.effect_parameters.duplicate(true)
	if not _apply_flat_numeric_overlay(parameters, growth, "effectAdd.", "effectMul."):
		return null
	result.effect_parameters = parameters
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
