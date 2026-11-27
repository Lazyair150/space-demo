extends Resource
class_name SpaceRoguelikeIndividualLibrary
## Shared library for obtainable parser, workshop and skill definition instances.
## Candidate selection is weighted across all eligible entries; pool boundaries retain their own model/budget.

@export var library_id: StringName = &""
@export var definition_version: int = 1
@export var pools: Array[SpaceRoguelikeIndividualPool] = []

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if library_id == &"" or definition_version <= 0:
		errors.append("individual library requires a stable versioned identity")
	var pool_keys := {}
	for pool in pools:
		if pool == null:
			errors.append("individual library cannot contain a null pool")
			continue
		errors.append_array(pool.get_validation_errors())
		var key := "%s:%s@%d" % [pool.item_kind, String(pool.pool_id), pool.definition_version]
		if pool_keys.has(key):
			errors.append("individual library contains duplicate pool identity: " + key)
		pool_keys[key] = true
	for required_kind in SpaceRoguelikeIndividualPool.SUPPORTED_KINDS:
		var found := false
		for pool in pools:
			if pool != null and pool.item_kind == required_kind:
				found = true
				break
		if not found:
			errors.append("individual library is missing an obtainable pool for " + required_kind)
	return errors

func is_valid() -> bool:
	return get_validation_errors().is_empty()

## One weighted draw across every eligible entry. This avoids selecting an empty pool
## while another pool of the same item kind still has valid candidates.
func roll_candidate(item_kind: String, rng: RandomNumberGenerator, allowed_rarities: PackedStringArray = PackedStringArray(), required_tags: PackedStringArray = PackedStringArray(), excluded_definition_keys: PackedStringArray = PackedStringArray()) -> Dictionary:
	if rng == null or not is_valid() or not SpaceRoguelikeIndividualPool.SUPPORTED_KINDS.has(item_kind):
		return {"success": false, "reason": "individual library is invalid or item kind is unsupported"}
	var candidates: Array[Dictionary] = []
	var total_weight := 0.0
	for pool in pools:
		if pool.item_kind != item_kind:
			continue
		for entry in pool.entries:
			var rarity := String(entry.get("rarity", ""))
			if not allowed_rarities.is_empty() and not allowed_rarities.has(rarity):
				continue
			var definition_key := "%s:%s@%d" % [item_kind, String(entry.get("definitionId", "")), int(entry.get("definitionVersion", 0))]
			if excluded_definition_keys.has(definition_key):
				continue
			var entry_tags: Array = entry.get("tags", [])
			var matches := true
			for required_tag in required_tags:
				if not entry_tags.has(String(required_tag)):
					matches = false
					break
			if not matches:
				continue
			var weight := float(entry.get("weight", 0.0))
			if weight <= 0.0 or not is_finite(weight):
				continue
			candidates.append({"pool": pool, "entry": entry, "weight": weight})
			total_weight += weight
	if candidates.is_empty() or total_weight <= 0.0:
		return {"success": false, "reason": "no pool entry matches the requested constraints"}
	var ticket := rng.randf() * total_weight
	for candidate in candidates:
		ticket -= float(candidate.weight)
		if ticket < 0.0:
			return _candidate_data(candidate.pool, candidate.entry)
	var last: Dictionary = candidates.back()
	return _candidate_data(last.pool, last.entry)

static func _candidate_data(pool: SpaceRoguelikeIndividualPool, entry: Dictionary) -> Dictionary:
	return {
		"success": true,
		"itemKind": pool.item_kind,
		"poolId": String(pool.pool_id),
		"poolVersion": pool.definition_version,
		"powerModelId": String(pool.power_model_id),
		"powerModelVersion": pool.power_model_version,
		"definitionId": String(entry.definitionId),
		"definitionVersion": int(entry.definitionVersion),
		"rarity": String(entry.rarity),
		"powerScore": float(entry.powerScore),
		"powerBand": pool.power_bands[String(entry.rarity)].duplicate(true),
		"powerMetrics": entry.powerMetrics.duplicate(true),
		"tags": entry.get("tags", []).duplicate(true)
	}

func resolve_pool(item_kind: String, pool_id: String, pool_version: int) -> SpaceRoguelikeIndividualPool:
	if not is_valid():
		return null
	for pool in pools:
		if pool != null and pool.item_kind == item_kind and String(pool.pool_id) == pool_id and pool.definition_version == pool_version:
			return pool.duplicate(true) as SpaceRoguelikeIndividualPool
	return null
