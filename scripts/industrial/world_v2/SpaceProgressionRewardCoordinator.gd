extends RefCounted
class_name SpaceProgressionRewardCoordinator
## Consumes durable campaign-clear fact envelopes through the versioned policy and
## the idempotent progression settlement service. Campaign and progression saves
## remain separate aggregates; the campaign record is the retryable outbox.

static func prepare_record(
	campaign_record: Dictionary,
	reward_profile: SpaceProgressionRewardProfile
) -> Dictionary:
	if reward_profile == null or not reward_profile.is_valid():
		return _failure("an exact valid Reward Profile is required")
	var stage_id := _required_text(campaign_record, "stageId")
	var raw_version: Variant = campaign_record.get("definitionVersion", null)
	var raw_result: Variant = campaign_record.get("result", null)
	if stage_id.is_empty() or typeof(raw_version) != TYPE_INT or int(raw_version) <= 0 or not (raw_result is Dictionary):
		return _failure("campaign clear record lacks exact Stage identity or result")
	var result: Dictionary = raw_result
	if String(result.get("status", "")) != "objective_complete":
		return _failure("only an objective-complete campaign record can produce progression rewards")
	var raw_identity: Variant = result.get("stageIdentity", null)
	if not (raw_identity is Dictionary):
		return _failure("durable Stage result has no exact Stage identity")
	if _required_text(raw_identity, "stageId") != stage_id or int(raw_identity.get("definitionVersion", 0)) != int(raw_version):
		return _failure("campaign record and durable result Stage identities do not match")
	var settlement_id := _required_text(result, "progressionRewardSettlementId")
	var raw_facts: Variant = result.get("progressionRewardFacts", null)
	if settlement_id.is_empty() or not (raw_facts is Array) or raw_facts.is_empty():
		return _failure("campaign clear record has no durable progression reward outbox")
	var expected_stage_ref := stage_id + "@" + str(int(raw_version))
	var has_stage_fact := false
	for raw_fact in raw_facts:
		if not (raw_fact is Dictionary):
			return _failure("durable progression reward outbox contains a malformed fact")
		if String(raw_fact.get("sourceKind", "")) == "battle_objective_completed" and String(raw_fact.get("sourceRef", "")) == expected_stage_ref:
			has_stage_fact = true
	if not has_stage_fact:
		return _failure("durable progression reward outbox does not contain this exact Stage-clear fact")
	var built := reward_profile.build_awards(raw_facts)
	if not bool(built.get("success", false)):
		return _failure("Reward Profile rejected the durable facts: " + String(built.get("reason", "")))
	return {
		"success": true,
		"settlementId": settlement_id,
		"stageId": stage_id,
		"definitionVersion": int(raw_version),
		"rewardProfileId": String(built.get("rewardProfileId", "")),
		"rewardProfileVersion": int(built.get("rewardProfileVersion", 0)),
		"awards": built.get("awards", [])
	}

## Re-entry recovery is intentionally safe to call on every Hangar entry.
## Exact duplicate receipts are successful no-op commits; changed policy payloads
## under the same settlement ID are rejected by SpaceProgressionRewardService.
static func recover_pending(
	game_state: Node,
	reward_profile: SpaceProgressionRewardProfile,
	curve_catalog: SpaceProgressionCurveCatalog
) -> Dictionary:
	if game_state == null or reward_profile == null or curve_catalog == null:
		return _failure("GameState, Reward Profile and Curve Catalog are all required")
	if not game_state.has_method("commit_space_progression_reward_settlement"):
		return _failure("GameState does not expose the durable progression settlement boundary")
	var campaign: Variant = game_state.get("space_campaign_progress_state")
	var progression: Variant = game_state.get("space_progression_state")
	if not (campaign is SpaceCampaignProgressState) or not (progression is SpacePlayerProgressionState):
		return _failure("campaign or player progression aggregate is not loaded")
	var summary := {"success": true, "settled": 0, "duplicates": 0, "skippedLegacy": 0, "pending": 0}
	for record in campaign.cleared_stage_records:
		if not (record is Dictionary):
			summary["pending"] = int(summary["pending"]) + 1
			summary["success"] = false
			summary["reason"] = "campaign clear ledger contains a malformed record"
			break
		var result: Variant = record.get("result", null)
		if not (result is Dictionary) or not result.has("progressionRewardSettlementId"):
			summary["skippedLegacy"] = int(summary["skippedLegacy"]) + 1
			continue
		var prepared := prepare_record(record, reward_profile)
		if not bool(prepared.get("success", false)):
			summary["pending"] = int(summary["pending"]) + 1
			summary["success"] = false
			summary["reason"] = String(prepared.get("reason", "reward outbox preparation failed"))
			break
		var committed: Dictionary = game_state.call(
			"commit_space_progression_reward_settlement",
			game_state.get("space_progression_state"),
			curve_catalog,
			String(prepared["settlementId"]),
			prepared["awards"]
		)
		if not bool(committed.get("success", false)):
			summary["pending"] = int(summary["pending"]) + 1
			summary["success"] = false
			summary["reason"] = String(committed.get("reason", "progression reward save failed"))
			break
		if bool(committed.get("duplicate", false)):
			summary["duplicates"] = int(summary["duplicates"]) + 1
		else:
			summary["settled"] = int(summary["settled"]) + 1
	return summary

static func _required_text(source: Dictionary, key: String) -> String:
	var raw: Variant = source.get(key, null)
	return String(raw) if typeof(raw) == TYPE_STRING and String(raw) == String(raw).strip_edges() else ""

static func _failure(reason: String) -> Dictionary:
	return {"success": false, "reason": reason}
