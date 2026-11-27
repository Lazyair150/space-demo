extends RefCounted
class_name SpaceBattleRewardFactProjectionProbe
## Synthetic identities verify stable fact projection; no production XP values are used.

static func run() -> Dictionary:
	var parser_owned_instance := {
		"instanceId": "probe.parser.owned",
		"itemKind": "ore_parser",
		"definitionId": "probe.parser.definition",
		"definitionVersion": 1,
		"level": 1,
		"experience": 0,
		"progressionRevision": 1
	}
	var parser_profile := {
		"parserId": "probe.parser.definition",
		"definitionVersion": 1,
		"ownedInstance": parser_owned_instance.duplicate(true)
	}
	var expected_runtime_parser_id := SpaceOreParserRuntime.build_runtime_instance_id(
		"probe-world-01", parser_profile
	)
	if expected_runtime_parser_id != "probe-world-01:owned:probe.parser.owned":
		return _failure("production Parser runtime identity was not scoped to its exact World and Owned Instance")
	var loadout := {
		"shipWorldId": "probe-world-01",
		"shipSelection": {"ownedInstance": {"instanceId": "probe.ship.owned"}},
		"productionDeviceSelections": [
			{
				"deviceKind": "ore_parser",
				"definitionId": "probe.parser.definition",
				"definitionVersion": 1,
				"ownedInstance": parser_owned_instance.duplicate(true),
				"oreParserProfile": parser_profile.duplicate(true)
			}
		]
	}
	var parser_checkpoint := {
		"schemaVersion": 2,
		"parserRuntime": {
			"schemaVersion": 5,
			"parserInstanceId": expected_runtime_parser_id,
			"seenPickups": {
				"space-stone:probe-world-01:2": {"stoneType": "square", "originalVolumeMicro": 2000000},
				"space-stone:probe-world-01:1": {"stoneType": "round", "originalVolumeMicro": 1000000}
			}
		}
	}
	var stage_result := {
		"status": "objective_complete",
		"stageIdentity": {"stageId": "drift_perimeter", "definitionVersion": 1}
	}
	var projected := SpaceBattleRewardFactProjection.build_facts(loadout, parser_checkpoint, stage_result, true)
	if not bool(projected.get("success", false)):
		return _failure("valid battle facts could not be projected: " + String(projected.get("reason", "")))
	var facts: Variant = projected.get("facts", null)
	if not (facts is Array) or facts.size() != 3:
		return _failure("accepted Pickups plus durable Stage-clear candidate did not produce three facts")
	if String(projected.get("settlementId", "")) != "space-stage-reward:probe-world-01:drift_perimeter@1":
		return _failure("stage reward settlement identity is not stable and exact")
	for fact in facts:
		if String(fact.get("instanceId", "")) != "probe.ship.owned":
			return _failure("Ship reward fact was not attributed to the exact frozen Ship Owned Instance")
	if String(facts[0].get("eventId", "")) >= String(facts[1].get("eventId", "")):
		return _failure("reward facts are not deterministically sorted")
	if not projected.get("notYetCapturedSourceKinds", []).has("parser_volume_processed"):
		return _failure("projection falsely claims Parser processed-volume facts are available")

	var without_stage := SpaceBattleRewardFactProjection.build_facts(loadout, parser_checkpoint)
	if not bool(without_stage.get("success", false)) or without_stage.get("facts", []).size() != 2:
		return _failure("non-terminal battle projection must retain accepted Pickups without inventing Stage clear")
	if not String(without_stage.get("settlementId", "")).is_empty():
		return _failure("non-terminal battle projection must not invent a Stage reward settlement ID")

	var mismatched_parser := parser_checkpoint.duplicate(true)
	mismatched_parser["parserRuntime"]["parserInstanceId"] = "another-world:owned:another.parser"
	if bool(SpaceBattleRewardFactProjection.build_facts(loadout, mismatched_parser).get("success", false)):
		return _failure("Parser checkpoint from another Owned Instance was accepted")

	var wrong_world_loadout := loadout.duplicate(true)
	wrong_world_loadout["shipWorldId"] = "probe-world-02"
	if bool(SpaceBattleRewardFactProjection.build_facts(wrong_world_loadout, parser_checkpoint).get("success", false)):
		return _failure("Parser checkpoint from another ship World was accepted")

	var wrong_profile_loadout := loadout.duplicate(true)
	var wrong_profile_device: Dictionary = wrong_profile_loadout["productionDeviceSelections"][0]
	var wrong_profile: Dictionary = wrong_profile_device["oreParserProfile"]
	var wrong_profile_owned: Dictionary = wrong_profile["ownedInstance"]
	wrong_profile_owned["instanceId"] = "another.parser"
	wrong_profile["ownedInstance"] = wrong_profile_owned
	wrong_profile_device["oreParserProfile"] = wrong_profile
	wrong_profile_loadout["productionDeviceSelections"][0] = wrong_profile_device
	if bool(SpaceBattleRewardFactProjection.build_facts(wrong_profile_loadout, parser_checkpoint).get("success", false)):
		return _failure("composed Parser profile detached from its frozen Owned Instance was accepted")

	# The runtime identity builder explicitly supports restoring a legacy
	# definition-scoped checkpoint without changing its pending Operation ID namespace.
	var legacy_checkpoint := parser_checkpoint.duplicate(true)
	legacy_checkpoint["parserRuntime"]["parserInstanceId"] = "probe-world-01:probe.parser.definition"
	var legacy_projection := SpaceBattleRewardFactProjection.build_facts(loadout, legacy_checkpoint, stage_result, true)
	if not bool(legacy_projection.get("success", false)):
		return _failure("supported legacy Parser checkpoint identity could not be projected")

	var invalid_stage := stage_result.duplicate(true)
	invalid_stage["status"] = "objective_failed"
	if bool(SpaceBattleRewardFactProjection.build_facts(loadout, parser_checkpoint, invalid_stage, true).get("success", false)):
		return _failure("failed Stage was allowed to emit a completion reward fact")

	return {
		"passed": true,
		"pickupFacts": 2,
		"stageClearFacts": 1,
		"worldScopedParserIdentity": expected_runtime_parser_id,
		"legacyParserIdentityAccepted": true
	}

static func _failure(reason: String) -> Dictionary:
	return {"passed": false, "reason": reason}
