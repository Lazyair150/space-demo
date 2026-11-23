extends Resource
class_name SpaceRoguelikeIndividualLibrary
## Shared library for obtainable parser, workshop and skill definition instances.
## It rolls definition candidates only; ownership/acquisition is committed by progression services.

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

func roll_candidate(item_kind: String, rng: RandomNumberGenerator, allowed_rarities: PackedStringArray = PackedStringArray(), required_tags: PackedStringArray = PackedStringArray(), excluded_definition_keys: PackedStringArray = PackedStringArray()) -> Dictionary:
	if not is_valid() or not SpaceRoguelikeIndividualPool.SUPPORTED_KINDS.has(item_kind):
		return {"success": false, "reason": "individual library is invalid or item kind is unsupported"}
	var candidates: Array[SpaceRoguelikeIndividualPool] = []
	for pool in pools:
		if pool.item_kind == item_kind:
			candidates.append(pool)
	if candidates.is_empty():
		return {"success": false, "reason": "no pool exists for requested item kind"}
	# Select among pools uniformly, then use each pool's explicit weighted entry distribution.
	# A future run reward policy may supply a pool selector without changing entry semantics.
	var selected_pool := candidates[rng.randi_range(0, candidates.size() - 1)]
	return selected_pool.roll_candidate(rng, allowed_rarities, required_tags, excluded_definition_keys)
