extends Resource
class_name SpaceRoguelikeIndividualPool
## Versioned weighted reward pool. Power bands are authored by rarity and item kind.

const SUPPORTED_KINDS := ["ore_parser", "workshop", "skill"]

@export var pool_id: StringName = &""
@export var definition_version: int = 1
@export var power_model_id: StringName = &""
@export var power_model_version: int = 1
@export var power_model: SpaceIndividualPowerModelDefinition
@export_enum("ore_parser", "workshop", "skill") var item_kind: String = "skill"
## rarity -> {"minimum": float, "maximum": float}; bounds are inclusive.
@export var power_bands: Dictionary = {}
## Entries carry exact catalog identity and an explicit normalized power score.
@export var entries: Array[Dictionary] = []

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if pool_id == &"" or definition_version <= 0 or power_model_id == &"" or power_model_version <= 0 or not SUPPORTED_KINDS.has(item_kind):
		errors.append("individual pool requires a stable versioned supported item kind")
	if power_model == null or not power_model.get_validation_errors().is_empty() or String(power_model.model_id) != String(power_model_id) or power_model.definition_version != power_model_version or power_model.item_kind != item_kind:
		errors.append("pool must reference its exact matching subsystem power model version")
	if power_bands.is_empty():
		errors.append("individual pool requires at least one rarity power band")
	for rarity in power_bands:
		var band: Variant = power_bands[rarity]
		if String(rarity).strip_edges().is_empty() or not (band is Dictionary):
			errors.append("rarity power band must be a named dictionary")
			continue
		var minimum: Variant = band.get("minimum", null)
		var maximum: Variant = band.get("maximum", null)
		if not _valid_number(minimum) or not _valid_number(maximum) or float(minimum) < 0.0 or float(maximum) < float(minimum):
			errors.append("rarity power band bounds are invalid: " + String(rarity))
	var identities := {}
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var definition_id := String(entry.get("definitionId", "")).strip_edges()
		var version: Variant = entry.get("definitionVersion", null)
		var rarity := String(entry.get("rarity", ""))
		var power: Variant = entry.get("powerScore", null)
		var metrics: Variant = entry.get("powerMetrics", null)
		var weight: Variant = entry.get("weight", null)
		var key := "%s:%s@%d" % [item_kind, definition_id, int(version) if typeof(version) == TYPE_INT else 0]
		if definition_id.is_empty() or typeof(version) != TYPE_INT or int(version) <= 0 or identities.has(key):
			errors.append("pool entry %d has missing/duplicate exact definition identity" % index)
		else:
			identities[key] = true
		if not (metrics is Dictionary) or power_model == null:
			errors.append("pool entry %d requires metrics from its subsystem power model" % index)
		else:
			var calculated := power_model.calculate_power_score(metrics)
			if not bool(calculated.get("success", false)) or not _valid_number(power) or absf(float(calculated.get("powerScore", -1.0)) - float(power)) > 0.000001:
				errors.append("pool entry %d power score does not match its subsystem model metrics" % index)
		if not power_bands.has(rarity):
			errors.append("pool entry %d references an undefined rarity band" % index)
		elif not _valid_number(power) or float(power) < float(power_bands[rarity].minimum) or float(power) > float(power_bands[rarity].maximum):
			errors.append("pool entry %d is under/over its rarity power band" % index)
		if not _valid_number(weight) or float(weight) <= 0.0:
			errors.append("pool entry %d requires a positive finite weight" % index)
		var tags: Variant = entry.get("tags", [])
		if not (tags is Array):
			errors.append("pool entry %d tags must be an array" % index)
	return errors

func is_valid() -> bool:
	return get_validation_errors().is_empty()

func roll_candidate(rng: RandomNumberGenerator, allowed_rarities: PackedStringArray = PackedStringArray(), required_tags: PackedStringArray = PackedStringArray(), excluded_definition_keys: PackedStringArray = PackedStringArray()) -> Dictionary:
	if rng == null or not is_valid():
		return {"success": false, "reason": "pool or random source is invalid"}
	var candidates: Array[Dictionary] = []
	var total_weight := 0.0
	for entry in entries:
		var rarity := String(entry.rarity)
		if not allowed_rarities.is_empty() and not allowed_rarities.has(rarity):
			continue
		var key := "%s:%s@%d" % [item_kind, String(entry.definitionId), int(entry.definitionVersion)]
		if excluded_definition_keys.has(key):
			continue
		var entry_tags: Array = entry.get("tags", [])
		var matches := true
		for required_tag in required_tags:
			if not entry_tags.has(String(required_tag)):
				matches = false
				break
		if not matches:
			continue
		candidates.append(entry)
		total_weight += float(entry.weight)
	if candidates.is_empty() or total_weight <= 0.0:
		return {"success": false, "reason": "no pool entry matches the requested constraints"}
	var ticket := rng.randf() * total_weight
	for entry in candidates:
		ticket -= float(entry.weight)
		if ticket < 0.0:
			return {
				"success": true,
				"itemKind": item_kind,
				"poolId": String(pool_id),
				"poolVersion": definition_version,
				"powerModelId": String(power_model_id),
				"powerModelVersion": power_model_version,
				"definitionId": String(entry.definitionId),
				"definitionVersion": int(entry.definitionVersion),
				"rarity": String(entry.rarity),
				"powerScore": float(entry.powerScore),
				"powerBand": power_bands[String(entry.rarity)].duplicate(true),
				"powerMetrics": entry.powerMetrics.duplicate(true),
				"tags": entry.get("tags", []).duplicate(true)
			}
	var last: Dictionary = candidates.back()
	return {
		"success": true,
		"itemKind": item_kind,
		"poolId": String(pool_id),
		"poolVersion": definition_version,
		"powerModelId": String(power_model_id),
		"powerModelVersion": power_model_version,
		"definitionId": String(last.definitionId),
		"definitionVersion": int(last.definitionVersion),
		"rarity": String(last.rarity),
		"powerScore": float(last.powerScore),
		"powerBand": power_bands[String(last.rarity)].duplicate(true),
		"powerMetrics": last.powerMetrics.duplicate(true),
		"tags": last.get("tags", []).duplicate(true)
	}

func validate_effective_power(definition_id: String, version: int, rarity: String, effective_power_score: float) -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_valid():
		errors.append_array(get_validation_errors())
		return errors
	var found := false
	for entry in entries:
		if String(entry.definitionId) == definition_id and int(entry.definitionVersion) == version and String(entry.rarity) == rarity:
			found = true
			break
	if not found:
		errors.append("effective power validation requires an exact pool entry identity")
		return errors
	if not is_finite(effective_power_score):
		errors.append("effective power score must be finite")
		return errors
	var band: Dictionary = power_bands[rarity]
	if effective_power_score < float(band.minimum) or effective_power_score > float(band.maximum):
		errors.append("owned instance effective power is under/over its rarity budget")
	return errors

func validate_effective_metrics(definition_id: String, version: int, rarity: String, metrics: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if power_model == null:
		errors.append("pool has no subsystem power model")
		return errors
	var calculated := power_model.calculate_power_score(metrics)
	if not bool(calculated.get("success", false)):
		errors.append(String(calculated.get("reason", "power model rejected metrics")))
		return errors
	return validate_effective_power(definition_id, version, rarity, float(calculated.powerScore))

func _valid_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
