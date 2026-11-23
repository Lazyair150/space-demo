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
	skill_pool.entries.append({
		"definitionId": "probe.skills.second.item",
		"definitionVersion": 1,
		"rarity": "rare",
		"powerScore": 4.0,
		"powerMetrics": {"normalized_strength": 0.4},
		"weight": 2.0,
		"tags": ["offense", "advanced"]
	})
	var offer_rng := RandomNumberGenerator.new()
	offer_rng.seed = 55421
	var offer := SpaceRoguelikeIndividualOfferService.roll_offer(library, "skill", offer_rng, 2, "probe.offer.distinct")
	if not bool(offer.get("success", false)) or offer.offers.size() != 2:
		return false
	var offered_keys := {}
	for item in offer.offers:
		var key := "%s@%d" % [String(item.definitionId), int(item.definitionVersion)]
		if offered_keys.has(key):
			return false
		offered_keys[key] = true
	if offered_keys.size() != 2:
		return false
	var excluded := library.roll_candidate("skill", rng_a, PackedStringArray(), PackedStringArray(), PackedStringArray(["skill:probe.skills.item@1", "skill:probe.skills.second.item@1"]))
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
		# The real-catalog acquisition fixture contains only the exact registered skill;
		# the synthetic second entry is retained only for distinct-offer coverage above.
		skill_pool.entries = [skill_pool.entries[0]]
		var reward_library := SpaceRoguelikeIndividualLibrary.new()
		reward_library.library_id = &"probe.reward-library"
		reward_library.definition_version = 1
		reward_library.pools = [parser_pool, workshop_pool, skill_pool]
		var reward_rng := RandomNumberGenerator.new()
		reward_rng.seed = 98231
		var reward_offer := SpaceRoguelikeIndividualOfferService.roll_offer(reward_library, "skill", reward_rng, 3, "probe.offer.real-acquisition")
		if not bool(reward_offer.get("success", false)) or reward_offer.offers.size() != 1:
			return false
		var acquired := SpaceRoguelikeIndividualOfferService.acquire_selected(reward_offer, 0, state, bundle, reward_library, "probe.roguelike-owned-copy")
		if not bool(acquired.get("success", false)) or state.resolve_instance("probe.roguelike-owned-copy") == null:
			return false
		if not state.reward_acquisition_ids.has(String(reward_offer.offerId)):
			return false
		var restored_reward_state := SpacePlayerProgressionState.from_data(state.to_data())
		if restored_reward_state == null or not restored_reward_state.reward_acquisition_ids.has(String(reward_offer.offerId)):
			return false
		var owned_count_after_reward := state.owned_instances.size()
		var duplicate_acquire := SpaceRoguelikeIndividualOfferService.acquire_selected(reward_offer, 0, state, bundle, reward_library, "probe.roguelike-owned-copy-duplicate")
		if bool(duplicate_acquire.get("success", false)) or state.owned_instances.size() != owned_count_after_reward:
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
	pool.require_definition_evaluation = false
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
