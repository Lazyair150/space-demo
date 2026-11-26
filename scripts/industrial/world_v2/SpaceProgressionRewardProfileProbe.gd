extends RefCounted
class_name SpaceProgressionRewardProfileProbe
## Synthetic content verifies policy mapping only; XP values here are not game balance.

static func run() -> Dictionary:
	var profile := SpaceProgressionRewardProfile.new()
	profile.profile_id = &"probe.reward-profile"
	profile.definition_version = 3
	profile.awards_by_source_kind = {
		"energy_stone_picked_up": {
			"itemKind": "ship",
			"experience": 4,
			"curveId": "probe.ship.curve",
			"curveVersion": 1
		},
		"parser_volume_processed": {
			"itemKind": "ore_parser",
			"experience": 6,
			"curveId": "probe.parser.curve",
			"curveVersion": 2
		}
	}
	if not profile.get_validation_errors().is_empty():
		return _failure("synthetic reward profile failed validation")

	var facts: Array[Dictionary] = [
		{
			"eventId": "probe.world:parser:02",
			"instanceId": "probe.parser.owned",
			"sourceKind": "parser_volume_processed",
			"sourceRef": "probe.parser.batch.02"
		},
		{
			"eventId": "probe.world:pickup:01",
			"instanceId": "probe.ship.owned",
			"sourceKind": "energy_stone_picked_up",
			"sourceRef": "probe.pickup.01"
		}
	]
	var built := profile.build_awards(facts)
	if not bool(built.get("success", false)):
		return _failure("committed facts could not be mapped: " + String(built.get("reason", "")))
	var awards: Variant = built.get("awards", null)
	if not (awards is Array) or awards.size() != 2:
		return _failure("reward profile did not produce the exact award count")
	if String(awards[0].get("eventId", "")) != "probe.world:parser:02":
		return _failure("reward profile output is not deterministically ordered")
	if String(awards[0].get("itemKind", "")) != "ore_parser" or int(awards[0].get("curveVersion", 0)) != 2:
		return _failure("Parser fact did not resolve its exact item kind and curve version")
	if String(awards[1].get("rewardProfileId", "")) != "probe.reward-profile" or int(awards[1].get("rewardProfileVersion", 0)) != 3:
		return _failure("award payload did not retain the exact reward policy identity")

	var unsupported_fact := {
		"eventId": "probe.world:unsupported:01",
		"instanceId": "probe.workshop.owned",
		"sourceKind": "workshop_rule_transition_committed",
		"sourceRef": "probe.rule-transition.01"
	}
	if bool(profile.build_awards([unsupported_fact]).get("success", false)):
		return _failure("missing source policy was silently ignored")

	var duplicate_facts: Array[Dictionary] = [facts[0].duplicate(true), facts[0].duplicate(true)]
	if bool(profile.build_awards(duplicate_facts).get("success", false)):
		return _failure("duplicate committed source event was accepted")

	var invalid_profile := profile.duplicate(true) as SpaceProgressionRewardProfile
	invalid_profile.awards_by_source_kind["energy_stone_picked_up"]["itemKind"] = "skill"
	if invalid_profile.get_validation_errors().is_empty():
		return _failure("incompatible source-to-item mapping was accepted")

	var empty_profile := SpaceProgressionRewardProfile.new()
	if empty_profile.get_validation_errors().is_empty():
		return _failure("empty reward profile silently supplied default reward values")

	return {
		"passed": true,
		"policyIdentity": "%s@%d" % [String(profile.profile_id), profile.definition_version],
		"mappedAwardCount": awards.size()
	}

static func _failure(reason: String) -> Dictionary:
	return {"passed": false, "reason": reason}
