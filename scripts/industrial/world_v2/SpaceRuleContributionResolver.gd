extends RefCounted
class_name SpaceRuleContributionResolver
## Resolves exact installed component Definitions + Owned Instance growth into a frozen,
## transport-safe contribution set. It does not interpret or execute any Core rule.

static func resolve(
	board_assignment_snapshot: Dictionary,
	bundle: SpaceHangarCatalogBundle,
	progression: SpacePlayerProgressionState
) -> Dictionary:
	if board_assignment_snapshot.is_empty() or bundle == null or progression == null:
		return {}
	var board: Dictionary = board_assignment_snapshot.get("boardDefinition", {})
	var assignments: Variant = board_assignment_snapshot.get("assignments", [])
	if String(board.get("boardId", "")) != String(board_assignment_snapshot.get("boardId", "")) or not (assignments is Array):
		return {}
	var contributions: Array[Dictionary] = []
	var seen_instances := {}
	for entry in assignments:
		if not (entry is Dictionary):
			return {}
		var slot_id := String(entry.get("slotId", ""))
		var kind := String(entry.get("componentKind", ""))
		var instance_id := String(entry.get("ownedInstanceId", ""))
		var instance := progression.resolve_instance(instance_id)
		if instance == null or seen_instances.has(instance_id):
			return {}
		seen_instances[instance_id] = true
		if instance.item_kind != kind or String(instance.definition_id) != String(entry.get("definitionId", "")) or instance.definition_version != int(entry.get("definitionVersion", 0)):
			return {}
		var definition: Resource = _resolve_definition(bundle, kind, String(entry.get("definitionId", "")), int(entry.get("definitionVersion", 0)))
		if definition == null:
			return {}
		if kind == "workshop":
			var workshop := definition as SpaceWorkshopDefinition
			if workshop == null:
				return {}
			for shape in workshop.base_marks:
				contributions.append(_builtin(instance, slot_id, "core.workshop.base-mark", "GrantBaseMark", String(shape)))
			for shape in workshop.additional_marks:
				contributions.append(_builtin(instance, slot_id, "core.workshop.additional-mark", "GrantAdditionalMark", String(shape)))
			for liquid in workshop.banned_liquids:
				contributions.append(_builtin(instance, slot_id, "core.workshop.ban-liquid", "BanLiquid", String(liquid)))
		var authored: Variant = definition.get("rule_contributions")
		if authored is Array:
			for contribution_definition in authored:
				if contribution_definition == null:
					return {}
				var resolved := contribution_definition.resolve(instance, slot_id)
				if resolved.is_empty():
					return {}
				contributions.append(resolved)
	var contribution_identities := {}
	for contribution in contributions:
		var source: Dictionary = contribution.get("source", {})
		var identity := "|".join([
			String(source.get("slotId", "")),
			String(source.get("sourceInstanceId", "")),
			String(contribution.get("ruleId", "")),
			str(int(contribution.get("ruleVersion", 0))),
			String(contribution.get("target", ""))
		])
		if contribution_identities.has(identity):
			return {}
		contribution_identities[identity] = true
	contributions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_source: Dictionary = a.get("source", {})
		var b_source: Dictionary = b.get("source", {})
		var a_key := String(a_source.get("slotId", "")) + "|" + String(a.get("ruleId", "")) + "|" + String(a_source.get("sourceInstanceId", ""))
		var b_key := String(b_source.get("slotId", "")) + "|" + String(b.get("ruleId", "")) + "|" + String(b_source.get("sourceInstanceId", ""))
		return a_key < b_key
	)
	var payload := {
		"schemaVersion": 1,
		"boardId": String(board_assignment_snapshot.get("boardId", "")),
		"boardDefinitionVersion": int(board_assignment_snapshot.get("definitionVersion", 0)),
		"assignmentFingerprint": String(board_assignment_snapshot.get("assignmentFingerprint", "")),
		"contributions": contributions
	}
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return {}
	hashing.update(JSON.stringify(_canonicalize(payload)).to_utf8_buffer())
	payload["fingerprint"] = hashing.finish().hex_encode()
	return payload

static func _resolve_definition(bundle: SpaceHangarCatalogBundle, kind: String, definition_id: String, version: int) -> Resource:
	match kind:
		"workshop":
			return bundle.workshop_catalog.resolve_definition(definition_id, version)
		"ore_parser":
			return bundle.ore_parser_catalog.resolve_definition(definition_id, version)
		"production_device":
			return bundle.production_device_catalog.resolve_definition(definition_id, version)
		"skill":
			return bundle.skill_catalog.resolve_skill(definition_id, version)
	return null

static func _builtin(
	instance: SpaceOwnedProgressionInstance,
	slot_id: String,
	rule_id: String,
	effect: String,
	target: String
) -> Dictionary:
	return {
		"ruleId": rule_id,
		"ruleVersion": 1,
		"effect": effect,
		"target": target,
		"scope": "workshop",
		"priority": 0,
		"source": {
			"sourceKind": "installed-component",
			"definitionId": String(instance.definition_id),
			"definitionVersion": instance.definition_version,
			"sourceInstanceId": String(instance.instance_id),
			"sourceRevision": instance.progression_revision,
			"slotId": slot_id
		},
		"parameters": {}
	}

static func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
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
