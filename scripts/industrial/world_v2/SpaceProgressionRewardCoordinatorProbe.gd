extends RefCounted
class_name SpaceProgressionRewardCoordinatorProbe
## Synthetic records verify durable-outbox consumption; values are not production balance data.

static func run() -> Dictionary:
	var profile := SpaceProgressionRewardProfile.new()
	profile.profile_id = &"probe.coordinator.profile"
	profile.definition_version = 2
	profile.awards_by_source_kind = {
		"battle_objective_completed": {
			"itemKind": "ship",
			"experience": 3,
			"curveId": "probe.ship.curve",
			"curveVersion": 1
		}
	}
	var record := {
		"stageId": "probe_stage",
		"definitionVersion": 1,
		"result": {
			"status": "objective_complete",
			"stageIdentity": {"stageId": "probe_stage", "definitionVersion": 1},
			"progressionRewardSettlementId": "space-stage-reward:probe-world:probe_stage@1",
			"progressionRewardFacts": [{
				"eventId": "space-reward:stage-clear:probe-world:probe_stage@1",
				"instanceId": "probe.ship.owned",
				"sourceKind": "battle_objective_completed",
				"sourceRef": "probe_stage@1"
			}]
		}
	}
	var prepared := SpaceProgressionRewardCoordinator.prepare_record(record, profile)
	if not bool(prepared.get("success", false)):
		return _failure("valid durable Stage outbox was rejected: " + String(prepared.get("reason", "")))
	if String(prepared.get("settlementId", "")) != "space-stage-reward:probe-world:probe_stage@1":
		return _failure("coordinator changed the stable settlement identity")
	var awards: Variant = prepared.get("awards", null)
	if not (awards is Array) or awards.size() != 1:
		return _failure("coordinator did not produce exactly one policy award")
	if String(awards[0].get("rewardProfileId", "")) != "probe.coordinator.profile" or int(awards[0].get("rewardProfileVersion", 0)) != 2:
		return _failure("coordinator dropped exact Reward Profile identity/version")

	var mismatched := record.duplicate(true)
	mismatched["definitionVersion"] = 2
	if bool(SpaceProgressionRewardCoordinator.prepare_record(mismatched, profile).get("success", false)):
		return _failure("campaign record/result Stage identity mismatch was accepted")
	var missing_stage_fact := record.duplicate(true)
	missing_stage_fact["result"]["progressionRewardFacts"][0]["sourceRef"] = "another_stage@1"
	if bool(SpaceProgressionRewardCoordinator.prepare_record(missing_stage_fact, profile).get("success", false)):
		return _failure("outbox without its exact Stage-clear fact was accepted")
	var unsupported := profile.duplicate(true) as SpaceProgressionRewardProfile
	unsupported.awards_by_source_kind.clear()
	if bool(SpaceProgressionRewardCoordinator.prepare_record(record, unsupported).get("success", false)):
		return _failure("invalid or incomplete Reward Profile was accepted")
	return {"passed": true, "stableSettlementId": String(prepared["settlementId"]), "awardCount": awards.size()}

static func _failure(reason: String) -> Dictionary:
	return {"passed": false, "reason": reason}
