extends RefCounted
class_name SpaceProgressionRewardServiceProbe
## Synthetic XP values exercise attribution and idempotency; they are not balance data.

static func run() -> Dictionary:
	var state := SpacePlayerProgressionState.new()
	state.player_id = &"progression-reward-probe"
	var ship := _instance("probe.ship.owned.01", "ship", "probe.ship", 1)
	var parser := _instance("probe.parser.owned.01", "ore_parser", "probe.parser", 1)
	if not state.unlock_and_acquire_instance(ship) or not state.unlock_and_acquire_instance(parser):
		return _failure("probe Owned Instances could not be acquired")
	var original_revision := state.state_revision

	var catalog := SpaceProgressionCurveCatalog.new()
	if not catalog.register_definition(_curve("probe.ship.curve", "ship", "stoneProgressRateMultiplier", 1.0, 1.25)):
		return _failure("ship progression curve could not be registered")
	if not catalog.register_definition(_curve("probe.parser.curve", "ore_parser", "shapeProcessingRateMultiplier", 1.0, 1.2)):
		return _failure("parser progression curve could not be registered")

	var awards: Array[Dictionary] = [
		{
			"eventId": "probe.run.01.pickup.01.ship",
			"instanceId": "probe.ship.owned.01",
			"itemKind": "ship",
			"sourceKind": "energy_stone_picked_up",
			"sourceRef": "probe.pickup.01",
			"experience": 7,
			"curveId": "probe.ship.curve",
			"curveVersion": 1
		},
		{
			"eventId": "probe.run.01.parser.01",
			"instanceId": "probe.parser.owned.01",
			"itemKind": "ore_parser",
			"sourceKind": "parser_volume_processed",
			"sourceRef": "probe.parser.receipt.01",
			"experience": 6,
			"curveId": "probe.parser.curve",
			"curveVersion": 1
		},
		{
			"eventId": "probe.run.01.parser.02",
			"instanceId": "probe.parser.owned.01",
			"itemKind": "ore_parser",
			"sourceKind": "parser_volume_processed",
			"sourceRef": "probe.parser.receipt.02",
			"experience": 5,
			"curveId": "probe.parser.curve",
			"curveVersion": 1
		}
	]
	var prepared := SpaceProgressionRewardService.prepare_settlement(
		state, catalog, "probe.run.01.settlement", awards
	)
	if not bool(prepared.get("success", false)) or bool(prepared.get("duplicate", true)):
		return _failure("first settlement was not prepared: " + String(prepared.get("reason", "")))
	var candidate: Variant = prepared.get("candidateState", null)
	if not (candidate is SpacePlayerProgressionState):
		return _failure("settlement did not return a detached progression candidate")
	if state.state_revision != original_revision or state.resolve_instance("probe.ship.owned.01").experience != 0:
		return _failure("preparing a settlement mutated the live source state")
	var candidate_state: SpacePlayerProgressionState = candidate as SpacePlayerProgressionState
	var updated_ship: SpaceOwnedProgressionInstance = candidate_state.resolve_instance("probe.ship.owned.01")
	var updated_parser: SpaceOwnedProgressionInstance = candidate_state.resolve_instance("probe.parser.owned.01")
	if updated_ship == null or updated_ship.experience != 7 or updated_ship.growth_curve_id != &"probe.ship.curve":
		return _failure("Ship XP was not attributed to the exact owned Ship")
	if updated_parser == null or updated_parser.experience != 11 or updated_parser.level != 2:
		return _failure("Parser committed work XP was not aggregated before curve application")
	var receipt_count: int = candidate_state.progression_reward_receipts.size()
	if receipt_count != 4:
		return _failure("settlement plus source event receipts were not persisted separately")
	if candidate_state.reward_acquisition_ids.size() != 0:
		return _failure("XP settlement incorrectly reused item acquisition receipts")

	var reversed_awards: Array[Dictionary] = []
	for index in range(awards.size() - 1, -1, -1):
		reversed_awards.append(awards[index].duplicate(true))
	var repeated := SpaceProgressionRewardService.prepare_settlement(
		candidate, catalog, "probe.run.01.settlement", reversed_awards
	)
	if not bool(repeated.get("success", false)) or not bool(repeated.get("duplicate", false)):
		return _failure("identical settlement replay was not recognized independent of event order")
	var replay_state: Variant = SpacePlayerProgressionState.from_data(candidate_state.to_data())
	if not (replay_state is SpacePlayerProgressionState) or replay_state.progression_reward_receipts.size() != receipt_count:
		return _failure("XP settlement receipts did not survive a schema-v3 save roundtrip")

	var conflicting_awards: Array[Dictionary] = awards.duplicate(true)
	conflicting_awards[0]["experience"] = 8
	var conflict := SpaceProgressionRewardService.prepare_settlement(
		candidate, catalog, "probe.run.01.settlement", conflicting_awards
	)
	if bool(conflict.get("success", false)):
		return _failure("same settlement ID with a different XP payload was not rejected")
	var replayed_event := SpaceProgressionRewardService.prepare_settlement(
		candidate, catalog, "probe.run.02.settlement", [awards[0]]
	)
	if bool(replayed_event.get("success", false)):
		return _failure("source event ID was allowed to award XP in a different settlement")

	var wrong_source := awards[0].duplicate(true)
	wrong_source["eventId"] = "probe.run.01.invalid.attribution"
	wrong_source["sourceKind"] = "workshop_rule_transition_committed"
	var attribution := SpaceProgressionRewardService.prepare_settlement(
		state, catalog, "probe.invalid.attribution", [wrong_source]
	)
	if bool(attribution.get("success", false)):
		return _failure("Workshop transition event was allowed to award Ship XP")

	var unknown_instance := awards[0].duplicate(true)
	unknown_instance["eventId"] = "probe.run.01.unknown.instance"
	unknown_instance["instanceId"] = "probe.ship.missing"
	var missing_instance := SpaceProgressionRewardService.prepare_settlement(
		state, catalog, "probe.invalid.instance", [unknown_instance]
	)
	if bool(missing_instance.get("success", false)):
		return _failure("reward event referencing an unowned Instance was accepted")

	var missing_curve := awards[0].duplicate(true)
	missing_curve["eventId"] = "probe.run.01.unknown.curve"
	missing_curve["curveId"] = "probe.missing.curve"
	var invalid_curve := SpaceProgressionRewardService.prepare_settlement(
		state, catalog, "probe.invalid.curve", [missing_curve]
	)
	if bool(invalid_curve.get("success", false)):
		return _failure("missing exact-version progression curve was accepted")

	var duplicate_event_awards: Array[Dictionary] = [awards[0].duplicate(true), awards[0].duplicate(true)]
	var duplicate_event := SpaceProgressionRewardService.prepare_settlement(
		state, catalog, "probe.invalid.duplicate-event", duplicate_event_awards
	)
	if bool(duplicate_event.get("success", false)):
		return _failure("duplicate event IDs in one settlement were accepted")

	var legacy_data: Dictionary = candidate.to_data()
	legacy_data["schemaVersion"] = 2
	legacy_data.erase("progressionRewardReceipts")
	if SpacePlayerProgressionState.from_data(legacy_data) == null:
		return _failure("schema-v2 progression save did not migrate without XP receipts")

	return {
		"passed": true,
		"settlementReceiptCount": receipt_count,
		"shipExperienceAwarded": updated_ship.experience,
		"parserExperienceAwarded": updated_parser.experience,
		"parserLevel": updated_parser.level,
		"stateRevisionAfterCandidate": candidate_state.state_revision
	}

static func _instance(instance_id: String, item_kind: String, definition_id: String, version: int) -> SpaceOwnedProgressionInstance:
	var instance := SpaceOwnedProgressionInstance.new()
	instance.instance_id = StringName(instance_id)
	instance.item_kind = item_kind
	instance.definition_id = StringName(definition_id)
	instance.definition_version = version
	return instance

static func _curve(curve_id: String, item_kind: String, attribute: String, level_one: float, level_three: float) -> SpaceProgressionCurveDefinition:
	var curve := SpaceProgressionCurveDefinition.new()
	curve.curve_id = StringName(curve_id)
	curve.definition_version = 1
	curve.item_kind = item_kind
	curve.max_level = 3
	curve.experience_threshold_by_level = {"2": 10, "3": 25}
	curve.attribute_keyframes = {
		attribute: [
			{"level": 1, "value": level_one},
			{"level": 3, "value": level_three}
		]
	}
	return curve

static func _failure(reason: String) -> Dictionary:
	return {"passed": false, "reason": reason}
