extends Resource
class_name SpaceProgressionRewardProfile
## Versioned content policy that converts committed source facts into final integer XP awards.
## It owns no runtime state and deliberately defines no default reward amounts.

const MAX_AWARDS_PER_SETTLEMENT: int = 4096
const MAX_TEXT_LENGTH: int = 256
const SOURCE_ITEM_KIND := {
	"energy_stone_picked_up": "ship",
	"battle_objective_completed": "ship",
	"parser_volume_processed": "ore_parser",
	"production_work_committed": "production_device",
	"workshop_rule_transition_committed": "workshop",
	"skill_effect_cycle_completed": "skill"
}
const RULE_FIELDS := ["itemKind", "experience", "curveId", "curveVersion"]
const FACT_FIELDS := ["eventId", "instanceId", "sourceKind", "sourceRef"]

@export var profile_id: StringName = &""
@export var definition_version: int = 1
## sourceKind -> { itemKind, experience, curveId, curveVersion }.
## Missing source rules are rejected; no source is silently skipped.
@export var awards_by_source_kind: Dictionary = {}

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if profile_id == &"" or String(profile_id).strip_edges().is_empty() or String(profile_id) != String(profile_id).strip_edges() or String(profile_id).length() > MAX_TEXT_LENGTH:
		errors.append("reward profile requires a canonical stable identity")
	if definition_version <= 0:
		errors.append("reward profile version must be positive")
	if awards_by_source_kind.is_empty():
		errors.append("reward profile must explicitly configure at least one source kind")
	for raw_source_kind in awards_by_source_kind:
		var source_kind := String(raw_source_kind)
		if not SOURCE_ITEM_KIND.has(source_kind):
			errors.append("reward profile contains an unsupported source kind: " + source_kind)
			continue
		var raw_rule: Variant = awards_by_source_kind[raw_source_kind]
		if not (raw_rule is Dictionary):
			errors.append("reward profile source rule must be a dictionary: " + source_kind)
			continue
		var rule: Dictionary = raw_rule
		for raw_key in rule:
			if not RULE_FIELDS.has(String(raw_key)):
				errors.append("reward profile source rule contains an unsupported field: " + String(raw_key))
		var item_kind := _required_text(rule, "itemKind")
		var curve_id := _required_text(rule, "curveId")
		var experience: Variant = rule.get("experience", null)
		var curve_version: Variant = rule.get("curveVersion", null)
		if item_kind != String(SOURCE_ITEM_KIND[source_kind]):
			errors.append("reward profile source kind has an incompatible item kind: " + source_kind)
		if not SpaceOwnedProgressionInstance.ITEM_KINDS.has(item_kind):
			errors.append("reward profile item kind is unsupported: " + item_kind)
		if experience == null or typeof(experience) != TYPE_INT or int(experience) <= 0:
			errors.append("reward profile experience must be a positive final integer: " + source_kind)
		if curve_id.is_empty() or curve_id != curve_id.strip_edges() or curve_id.length() > MAX_TEXT_LENGTH:
			errors.append("reward profile requires an exact non-empty curve identity: " + source_kind)
		if curve_version == null or typeof(curve_version) != TYPE_INT or int(curve_version) <= 0:
			errors.append("reward profile requires a positive exact curve version: " + source_kind)
	return errors

func is_valid() -> bool:
	return get_validation_errors().is_empty()

## Facts must already be committed by their authoritative subsystem.
## This method maps policy only; it does not manufacture or infer source facts.
func build_awards(committed_facts: Array) -> Dictionary:
	var errors := get_validation_errors()
	if not errors.is_empty():
		return _failure("reward profile is invalid: " + "; ".join(errors))
	if committed_facts.is_empty() or committed_facts.size() > MAX_AWARDS_PER_SETTLEMENT:
		return _failure("committed reward facts must contain 1..4096 entries")

	var event_ids := {}
	var awards: Array[Dictionary] = []
	for raw_fact in committed_facts:
		if not (raw_fact is Dictionary):
			return _failure("committed reward fact must be a dictionary")
		var fact: Dictionary = raw_fact
		for raw_key in fact:
			if not FACT_FIELDS.has(String(raw_key)):
				return _failure("committed reward fact contains an unsupported field: " + String(raw_key))
		var event_id := _required_text(fact, "eventId")
		var instance_id := _required_text(fact, "instanceId")
		var source_kind := _required_text(fact, "sourceKind")
		var source_ref := _required_text(fact, "sourceRef")
		var required_values := {
			"eventId": event_id,
			"instanceId": instance_id,
			"sourceKind": source_kind,
			"sourceRef": source_ref
		}
		for field_name in required_values:
			var value := String(required_values[field_name])
			if value.is_empty() or value.length() > MAX_TEXT_LENGTH or value != value.strip_edges():
				return _failure("committed reward fact requires canonical non-empty " + String(field_name))
		if event_ids.has(event_id):
			return _failure("committed reward event IDs must be unique: " + event_id)
		event_ids[event_id] = true
		if not awards_by_source_kind.has(source_kind):
			return _failure("reward profile has no explicit policy for committed source kind: " + source_kind)
		var rule: Dictionary = awards_by_source_kind[source_kind]
		awards.append({
			"eventId": event_id,
			"instanceId": instance_id,
			"itemKind": String(rule["itemKind"]),
			"sourceKind": source_kind,
			"sourceRef": source_ref,
			"experience": int(rule["experience"]),
			"curveId": String(rule["curveId"]),
			"curveVersion": int(rule["curveVersion"]),
			"rewardProfileId": String(profile_id),
			"rewardProfileVersion": definition_version
		})

	awards.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["eventId"]) < String(right["eventId"])
	)
	return {
		"success": true,
		"rewardProfileId": String(profile_id),
		"rewardProfileVersion": definition_version,
		"awards": awards
	}

static func _required_text(source: Dictionary, key: String) -> String:
	var raw: Variant = source.get(key, null)
	return String(raw) if typeof(raw) == TYPE_STRING else ""

static func _failure(reason: String) -> Dictionary:
	return {"success": false, "reason": reason}
