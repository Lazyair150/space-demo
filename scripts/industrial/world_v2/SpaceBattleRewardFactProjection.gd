extends RefCounted
class_name SpaceBattleRewardFactProjection
## Projects authoritative battle state into stable reward-source facts.
## It does not award XP or infer work from forecasts.

const MAX_TEXT_LENGTH: int = 256
const PARSER_RUNTIME_SCHEMA_VERSION: int = 5
const NOT_YET_CAPTURED_SOURCE_KINDS := [
	"parser_volume_processed",
	"production_work_committed",
	"workshop_rule_transition_committed",
	"skill_effect_cycle_completed"
]

static func build_facts(
	loadout_data: Dictionary,
	parser_checkpoint: Dictionary,
	stage_result: Dictionary = {},
	include_stage_clear_fact: bool = false
) -> Dictionary:
	var ship_world_id := _required_text(loadout_data, "shipWorldId")
	var ship_selection: Variant = loadout_data.get("shipSelection", null)
	if ship_world_id.is_empty() or not (ship_selection is Dictionary):
		return _failure("reward fact projection requires an exact frozen ship/loadout identity")
	var ship_instance: Variant = ship_selection.get("ownedInstance", null)
	if not (ship_instance is Dictionary):
		return _failure("reward fact projection requires the exact owned Ship Instance")
	var ship_instance_id := _required_text(ship_instance, "instanceId")
	if ship_instance_id.is_empty():
		return _failure("frozen Ship Owned Instance ID is missing")

	var parser_instance_id := ""
	var parser_owned_instance: Dictionary = {}
	var parser_profile: Dictionary = {}
	var parser_count := 0
	var devices: Variant = loadout_data.get("productionDeviceSelections", null)
	if not (devices is Array):
		return _failure("frozen production device selections are missing")
	for raw_device in devices:
		if not (raw_device is Dictionary) or String(raw_device.get("deviceKind", "")) != "ore_parser":
			continue
		parser_count += 1
		var owned_parser: Variant = raw_device.get("ownedInstance", null)
		var raw_profile: Variant = raw_device.get("oreParserProfile", null)
		if not (owned_parser is Dictionary) or not (raw_profile is Dictionary):
			return _failure("frozen Ore Parser must retain its exact Owned Instance and composed runtime profile")
		parser_owned_instance = owned_parser
		parser_profile = raw_profile
		parser_instance_id = _required_text(parser_owned_instance, "instanceId")
		if parser_instance_id.is_empty():
			return _failure("frozen Ore Parser Owned Instance ID is missing")
		if parser_profile.get("ownedInstance", null) != parser_owned_instance:
			return _failure("composed Parser profile does not retain the same frozen Owned Instance")
		if (
			_required_text(parser_profile, "parserId") != _required_text(raw_device, "definitionId")
			or int(parser_profile.get("definitionVersion", 0)) != int(raw_device.get("definitionVersion", 0))
		):
			return _failure("composed Parser profile differs from the frozen Parser Definition identity")
	if parser_count != 1 or parser_instance_id.is_empty():
		return _failure("reward fact projection requires exactly one owned Ore Parser")

	if int(parser_checkpoint.get("schemaVersion", 0)) != 2:
		return _failure("reward fact projection requires Parser checkpoint schema 2")
	var parser_runtime: Variant = parser_checkpoint.get("parserRuntime", null)
	if not (parser_runtime is Dictionary) or int(parser_runtime.get("schemaVersion", 0)) != PARSER_RUNTIME_SCHEMA_VERSION:
		return _failure("reward fact projection requires the current Parser runtime checkpoint")
	# Runtime identity is deliberately scoped to the ship World and exact Owned Parser.
	# Use the same canonicalizer as Game._initialize_ore_parser; it also preserves the
	# explicitly supported definition-scoped identity for a legacy checkpoint restore.
	var expected_runtime_identity := SpaceOreParserRuntime.build_runtime_instance_id(
		ship_world_id, parser_profile, parser_runtime
	)
	if expected_runtime_identity.is_empty():
		return _failure("frozen Owned Parser cannot produce a valid runtime identity")
	if String(parser_runtime.get("parserInstanceId", "")) != expected_runtime_identity:
		return _failure("Parser checkpoint identity does not match the frozen Owned Parser runtime identity")
	var seen_pickups: Variant = parser_runtime.get("seenPickups", null)
	if not (seen_pickups is Dictionary):
		return _failure("Parser accepted-pickup identity ledger is missing")

	var facts: Array[Dictionary] = []
	var event_ids := {}
	var pickup_ids: Array = seen_pickups.keys()
	pickup_ids.sort()
	for raw_pickup_id in pickup_ids:
		if typeof(raw_pickup_id) != TYPE_STRING:
			return _failure("Parser accepted-pickup ledger contains a non-string identity")
		var pickup_id := String(raw_pickup_id)
		var pickup_record: Variant = seen_pickups[raw_pickup_id]
		if pickup_id.is_empty() or pickup_id.length() > 128 or not (pickup_record is Dictionary):
			return _failure("Parser accepted-pickup ledger contains a malformed record")
		var stone_type := _required_text(pickup_record, "stoneType")
		var raw_volume: Variant = pickup_record.get("originalVolumeMicro", null)
		if stone_type.is_empty() or typeof(raw_volume) != TYPE_INT or int(raw_volume) <= 0:
			return _failure("Parser accepted-pickup record has invalid source data: " + pickup_id)
		var event_id := "space-reward:pickup:" + pickup_id
		if event_id.length() > MAX_TEXT_LENGTH or event_ids.has(event_id):
			return _failure("accepted pickup reward Event ID is invalid or duplicated: " + pickup_id)
		event_ids[event_id] = true
		facts.append({
			"eventId": event_id,
			"instanceId": ship_instance_id,
			"sourceKind": "energy_stone_picked_up",
			"sourceRef": pickup_id
		})

	var settlement_id := ""
	if include_stage_clear_fact:
		if String(stage_result.get("status", "")) != "objective_complete":
			return _failure("Stage reward fact requires an objective-complete stage result")
		var stage_identity: Variant = stage_result.get("stageIdentity", null)
		if not (stage_identity is Dictionary):
			return _failure("Stage reward fact requires an exact Stage identity")
		var stage_id := _required_text(stage_identity, "stageId")
		var raw_stage_version: Variant = stage_identity.get("definitionVersion", null)
		if stage_id.is_empty() or typeof(raw_stage_version) != TYPE_INT or int(raw_stage_version) <= 0:
			return _failure("Stage reward fact requires an exact Stage ID and positive version")
		settlement_id = "space-stage-reward:" + ship_world_id + ":" + stage_id + "@" + str(int(raw_stage_version))
		var event_id := "space-reward:stage-clear:" + ship_world_id + ":" + stage_id + "@" + str(int(raw_stage_version))
		if settlement_id.length() > MAX_TEXT_LENGTH or event_id.length() > MAX_TEXT_LENGTH or event_ids.has(event_id):
			return _failure("Stage reward settlement/Event identity is invalid or collides")
		facts.append({
			"eventId": event_id,
			"instanceId": ship_instance_id,
			"sourceKind": "battle_objective_completed",
			"sourceRef": stage_id + "@" + str(int(raw_stage_version))
		})

	facts.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["eventId"]) < String(right["eventId"])
	)
	var captured_source_kinds: Array[String] = []
	if not pickup_ids.is_empty():
		captured_source_kinds.append("energy_stone_picked_up")
	if include_stage_clear_fact:
		captured_source_kinds.append("battle_objective_completed")
	return {
		"success": true,
		"settlementId": settlement_id,
		"facts": facts,
		"capturedSourceKinds": captured_source_kinds,
		"notYetCapturedSourceKinds": NOT_YET_CAPTURED_SOURCE_KINDS.duplicate()
	}

static func _required_text(source: Dictionary, key: String) -> String:
	var raw: Variant = source.get(key, null)
	return String(raw) if typeof(raw) == TYPE_STRING and String(raw) == String(raw).strip_edges() else ""

static func _failure(reason: String) -> Dictionary:
	return {"success": false, "reason": reason}
