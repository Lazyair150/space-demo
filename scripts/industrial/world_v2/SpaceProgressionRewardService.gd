extends RefCounted
class_name SpaceProgressionRewardService
## Converts committed gameplay facts into per-Owned-Instance XP updates.
## This is a settlement boundary, not a reward-balance calculator:
## callers provide final integer XP after the versioned reward policy has applied.
##
## The whole settlement is prepared against a detached player aggregate. GameState
## persists that candidate before publishing it. Acquisition receipts remain separate.

const MAX_AWARDS_PER_SETTLEMENT := 4096
const MAX_TEXT_LENGTH := 256
const MAX_INT64: int = 9223372036854775807
const ALLOWED_FIELDS := [
	"eventId", "instanceId", "itemKind", "sourceKind", "sourceRef",
	"experience", "curveId", "curveVersion"
]
const SOURCE_ITEM_KIND := {
	"energy_stone_picked_up": "ship",
	"battle_objective_completed": "ship",
	"parser_volume_processed": "ore_parser",
	"production_work_committed": "production_device",
	"workshop_rule_transition_committed": "workshop",
	"skill_effect_cycle_completed": "skill"
}

static func prepare_settlement(
	source_state: SpacePlayerProgressionState,
	curve_catalog: SpaceProgressionCurveCatalog,
	settlement_id: String,
	raw_awards: Array
) -> Dictionary:
	if source_state == null or not source_state.get_validation_errors().is_empty():
		return _failure("player progression state is missing or invalid")
	if curve_catalog == null:
		return _failure("exact-version progression curve catalog is required")
	if settlement_id.strip_edges().is_empty() or settlement_id != settlement_id.strip_edges() or settlement_id.length() > MAX_TEXT_LENGTH:
		return _failure("settlement ID must be stable, non-empty and canonical")
	if raw_awards.is_empty() or raw_awards.size() > MAX_AWARDS_PER_SETTLEMENT:
		return _failure("settlement must contain 1..4096 committed reward events")

	var normalized_awards: Array[Dictionary] = []
	var event_ids := {}
	for raw in raw_awards:
		if not (raw is Dictionary):
			return _failure("reward event must be a dictionary")
		for raw_key in raw:
			if not ALLOWED_FIELDS.has(String(raw_key)):
				return _failure("reward event contains an unsupported field: " + String(raw_key))
		var event_id := _required_text(raw, "eventId")
		var instance_id := _required_text(raw, "instanceId")
		var item_kind := _required_text(raw, "itemKind")
		var source_kind := _required_text(raw, "sourceKind")
		var source_ref := _required_text(raw, "sourceRef")
		var curve_id := _required_text(raw, "curveId")
		var raw_experience: Variant = raw.get("experience", null)
		var raw_curve_version: Variant = raw.get("curveVersion", null)
		var required_values := {
			"eventId": event_id,
			"instanceId": instance_id,
			"itemKind": item_kind,
			"sourceKind": source_kind,
			"sourceRef": source_ref,
			"curveId": curve_id
		}
		for field_name in required_values:
			var value := String(required_values[field_name])
			if value.is_empty() or value.length() > MAX_TEXT_LENGTH or value != value.strip_edges():
				return _failure("reward event requires canonical non-empty " + String(field_name))
		if event_ids.has(event_id):
			return _failure("reward event IDs must be unique inside a settlement: " + event_id)
		event_ids[event_id] = true
		if not SOURCE_ITEM_KIND.has(source_kind) or String(SOURCE_ITEM_KIND[source_kind]) != item_kind:
			return _failure("reward source kind cannot award XP to this item kind: " + source_kind + "/" + item_kind)
		if not SpaceOwnedProgressionInstance.ITEM_KINDS.has(item_kind):
			return _failure("reward event item kind is unsupported: " + item_kind)
		if typeof(raw_experience) != TYPE_INT or int(raw_experience) <= 0:
			return _failure("reward experience must be a positive, already-rounded integer")
		if typeof(raw_curve_version) != TYPE_INT or int(raw_curve_version) <= 0:
			return _failure("reward curve version must be a positive integer")
		normalized_awards.append({
			"eventId": event_id,
			"instanceId": instance_id,
			"itemKind": item_kind,
			"sourceKind": source_kind,
			"sourceRef": source_ref,
			"experience": int(raw_experience),
			"curveId": curve_id,
			"curveVersion": int(raw_curve_version)
		})

	normalized_awards.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["eventId"]) < String(right["eventId"])
	)
	var settlement_fingerprint := _fingerprint(normalized_awards)
	if settlement_fingerprint.is_empty():
		return _failure("could not fingerprint the normalized reward settlement")

	var candidate := SpacePlayerProgressionState.from_data(source_state.to_data())
	if candidate == null:
		return _failure("could not create a detached progression candidate")
	var settlement_receipt_key := "settlement:" + settlement_id
	var prior_settlement_fingerprint := candidate.progression_reward_receipt_fingerprint(settlement_receipt_key)
	if not prior_settlement_fingerprint.is_empty():
		if prior_settlement_fingerprint == settlement_fingerprint:
			return {
				"success": true,
				"duplicate": true,
				"settlementId": settlement_id,
				"settlementFingerprint": settlement_fingerprint,
				"candidateState": candidate,
				"updatedInstances": [],
				"awardedExperienceByInstance": {}
			}
		return _failure("settlement ID was already committed with a different reward payload")

	for award in normalized_awards:
		var event_receipt_key := "event:" + String(award["eventId"])
		if not candidate.progression_reward_receipt_fingerprint(event_receipt_key).is_empty():
			return _failure("reward event was already claimed by another settlement: " + String(award["eventId"]))

	var grouped := {}
	for award in normalized_awards:
		var instance_id := String(award["instanceId"])
		var current := candidate.resolve_instance(instance_id)
		if current == null:
			return _failure("reward event references an unowned instance: " + instance_id)
		if current.item_kind != String(award["itemKind"]):
			return _failure("reward event item kind does not match the exact Owned Instance: " + instance_id)
		if not grouped.has(instance_id):
			grouped[instance_id] = {
				"itemKind": current.item_kind,
				"experience": 0,
				"curveId": String(award["curveId"]),
				"curveVersion": int(award["curveVersion"])
			}
		var group: Dictionary = grouped[instance_id]
		if String(group["curveId"]) != String(award["curveId"]) or int(group["curveVersion"]) != int(award["curveVersion"]):
			return _failure("one Owned Instance cannot use multiple growth curves in a single settlement")
		var previous_experience := int(group["experience"])
		var event_experience := int(award["experience"])
		if event_experience > MAX_INT64 - previous_experience:
			return _failure("aggregated reward experience exceeds Int64: " + instance_id)
		group["experience"] = previous_experience + event_experience
		grouped[instance_id] = group

	var updated_instances: Array[String] = []
	var awarded_experience_by_instance := {}
	var instance_ids: Array = grouped.keys()
	instance_ids.sort()
	for instance_value in instance_ids:
		var instance_id := String(instance_value)
		var group: Dictionary = grouped[instance_id]
		var current := candidate.resolve_instance(instance_id)
		if current == null or int(group["experience"]) > MAX_INT64 - current.experience:
			return _failure("Owned Instance experience would exceed Int64: " + instance_id)
		var curve := curve_catalog.resolve_definition(
			String(group["itemKind"]),
			String(group["curveId"]),
			int(group["curveVersion"])
		)
		if curve == null:
			return _failure("exact progression curve is missing: " + String(group["curveId"]) + "@" + str(group["curveVersion"]))
		var updated := SpaceProgressionGrowthService.calculate_update(
			current,
			curve,
			current.experience + int(group["experience"])
		)
		if updated == null or not candidate.replace_instance_progression(updated):
			return _failure("Owned Instance growth update was rejected: " + instance_id)
		updated_instances.append(instance_id)
		awarded_experience_by_instance[instance_id] = int(group["experience"])

	var receipt_entries := {}
	receipt_entries[settlement_receipt_key] = settlement_fingerprint
	for award in normalized_awards:
		var event_id := String(award["eventId"])
		receipt_entries["event:" + event_id] = _fingerprint(award)
	if not candidate.record_progression_reward_receipts(receipt_entries):
		return _failure("progression reward receipts could not be committed to the candidate")
	if not candidate.get_validation_errors().is_empty():
		return _failure("progression settlement candidate failed aggregate validation")
	return {
		"success": true,
		"duplicate": false,
		"settlementId": settlement_id,
		"settlementFingerprint": settlement_fingerprint,
		"candidateState": candidate,
		"updatedInstances": updated_instances,
		"awardedExperienceByInstance": awarded_experience_by_instance
	}

static func _required_text(source: Dictionary, key: String) -> String:
	var raw: Variant = source.get(key, null)
	return String(raw) if typeof(raw) == TYPE_STRING else ""

static func _fingerprint(value: Variant) -> String:
	var hasher := HashingContext.new()
	if hasher.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hasher.update(JSON.stringify(_canonicalize(value)).to_utf8_buffer())
	return hasher.finish().hex_encode()

static func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(left: Variant, right: Variant) -> bool: return String(left) < String(right))
		var result := {}
		for key in keys:
			result[key] = _canonicalize(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_canonicalize(item))
		return result
	return value

static func _failure(reason: String) -> Dictionary:
	return {"success": false, "reason": reason}
