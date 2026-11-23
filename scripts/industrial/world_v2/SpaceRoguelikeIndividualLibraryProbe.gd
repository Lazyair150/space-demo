extends RefCounted
class_name SpaceRoguelikeIndividualLibraryProbe

static func run(bundle: SpaceHangarCatalogBundle = null, state: SpacePlayerProgressionState = null, skill_id: String = "", skill_version: int = 1) -> bool:
	var parser_pool := _pool("probe.parsers", "ore_parser")
	var workshop_pool := _pool("probe.workshops", "workshop")
	var skill_pool := _pool("probe.skills", "skill")
	var library := SpaceRoguelikeIndividualLibrary.new()
	library.library_id = &"probe.roguelike-library"
	library.definition_version = 1
	library.pools = [parser_pool, workshop_pool, skill_pool]
	if not library.is_valid():
		return false
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 77123
	rng_b.seed = 77123
	var first := library.roll_candidate("skill", rng_a, PackedStringArray(["common"]), PackedStringArray(["offense"]))
	var second := library.roll_candidate("skill", rng_b, PackedStringArray(["common"]), PackedStringArray(["offense"]))
	if not bool(first.get("success", false)) or first != second:
		return false
	if float(first.powerScore) < float(first.powerBand.minimum) or float(first.powerScore) > float(first.powerBand.maximum):
		return false
	if not skill_pool.validate_effective_power(String(first.definitionId), int(first.definitionVersion), String(first.rarity), 2.5).is_empty():
		return false
	if skill_pool.validate_effective_power(String(first.definitionId), int(first.definitionVersion), String(first.rarity), 5.5).is_empty():
		return false
	if skill_pool.validate_effective_metrics(String(first.definitionId), int(first.definitionVersion), String(first.rarity), {"normalized_strength": 1.1}).is_empty():
		return false
	var excluded := library.roll_candidate("skill", rng_a, PackedStringArray(), PackedStringArray(), PackedStringArray(["skill:probe.skills.item@1"]))
	if bool(excluded.get("success", false)):
		return false
	var underpowered := _pool("probe.invalid-low", "skill")
	underpowered.entries[0].powerScore = 0.1
	underpowered.entries[0].powerMetrics.normalized_strength = 0.01
	if underpowered.is_valid():
		return false
	var overpowered := _pool("probe.invalid-high", "skill")
	overpowered.entries[0].powerScore = 9.0
	overpowered.entries[0].powerMetrics.normalized_strength = 0.9
	if overpowered.is_valid():
		return false
	if bundle != null or state != null:
		if bundle == null or state == null or skill_id.is_empty() or skill_version <= 0:
			return false
		skill_pool.entries[0].definitionId = skill_id
		skill_pool.entries[0].definitionVersion = skill_version
		var reward_library := SpaceRoguelikeIndividualLibrary.new()
		reward_library.library_id = &"probe.reward-library"
		reward_library.definition_version = 1
		reward_library.pools = [parser_pool, workshop_pool, skill_pool]
		var reward_rng := RandomNumberGenerator.new()
		reward_rng.seed = 98231
		var reward_candidate := reward_library.roll_candidate("skill", reward_rng)
		var acquired := SpaceRoguelikeIndividualRewardService.acquire_candidate(state, bundle, reward_library, reward_candidate, "probe.roguelike-owned-copy")
		if not bool(acquired.get("success", false)) or state.resolve_instance("probe.roguelike-owned-copy") == null:
			return false
	return true

static func _pool(id: String, kind: String) -> SpaceRoguelikeIndividualPool:
	var pool := SpaceRoguelikeIndividualPool.new()
	pool.pool_id = StringName(id)
	pool.definition_version = 1
	pool.power_model_id = StringName("probe.power." + kind)
	pool.power_model_version = 1
	var model := SpaceIndividualPowerModelDefinition.new()
	model.model_id = pool.power_model_id
	model.definition_version = pool.power_model_version
	model.item_kind = kind
	model.metric_dimensions = {"normalized_strength": {"minimum": 0.0, "maximum": 1.0, "weight": 1.0, "higherIsBetter": true}}
	pool.power_model = model
	pool.item_kind = kind
	pool.power_bands = {
		"common": {"minimum": 1.0, "maximum": 3.0},
		"rare": {"minimum": 3.1, "maximum": 5.0}
	}
	pool.entries = [{
		"definitionId": id + ".item",
		"definitionVersion": 1,
		"rarity": "common",
		"powerScore": 2.0,
		"powerMetrics": {"normalized_strength": 0.2},
		"weight": 1.0,
		"tags": ["offense"]
	}]
	return pool
