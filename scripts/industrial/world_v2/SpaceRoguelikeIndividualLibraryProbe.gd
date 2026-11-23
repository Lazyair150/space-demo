extends RefCounted
class_name SpaceRoguelikeIndividualLibraryProbe

static func run() -> bool:
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
	var excluded := library.roll_candidate("skill", rng_a, PackedStringArray(), PackedStringArray(), PackedStringArray(["skill:probe.skills.item@1"]))
	if bool(excluded.get("success", false)):
		return false
	var underpowered := _pool("probe.invalid-low", "skill")
	underpowered.entries[0].powerScore = 0.1
	if underpowered.is_valid():
		return false
	var overpowered := _pool("probe.invalid-high", "skill")
	overpowered.entries[0].powerScore = 9.0
	if overpowered.is_valid():
		return false
	return true

static func _pool(id: String, kind: String) -> SpaceRoguelikeIndividualPool:
	var pool := SpaceRoguelikeIndividualPool.new()
	pool.pool_id = StringName(id)
	pool.definition_version = 1
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
		"weight": 1.0,
		"tags": ["offense"]
	}]
	return pool
