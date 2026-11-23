extends RefCounted
class_name SpaceRoguelikeIndividualPoolEntryBuilder
## Creates production pool entries from exact subsystem definitions rather than hand-entered scores.

static func append_parser(
	pool: SpaceRoguelikeIndividualPool,
	definition: SpaceOreParserDefinition,
	shape_vocabulary: Array,
	rarity: String,
	weight: float,
	tags: Array = []
) -> Dictionary:
	if pool == null or pool.item_kind != "ore_parser":
		return _failure("parser entry requires an ore_parser pool")
	var evaluated := SpaceIndividualPowerEvaluator.evaluate_parser(definition, shape_vocabulary, pool.power_model)
	if not bool(evaluated.get("success", false)):
		return evaluated
	return _append(pool, definition.parser_id, definition.definition_version, rarity, weight, tags, evaluated, {
		"shapeVocabulary": shape_vocabulary.duplicate(true)
	})

static func append_workshop(
	pool: SpaceRoguelikeIndividualPool,
	definition: SpaceWorkshopDefinition,
	shape_vocabulary: Array,
	liquid_vocabulary: Array,
	rarity: String,
	weight: float,
	tags: Array = []
) -> Dictionary:
	if pool == null or pool.item_kind != "workshop":
		return _failure("workshop entry requires a workshop pool")
	var evaluated := SpaceIndividualPowerEvaluator.evaluate_workshop(definition, shape_vocabulary, liquid_vocabulary, pool.power_model)
	if not bool(evaluated.get("success", false)):
		return evaluated
	return _append(pool, definition.workshop_id, definition.definition_version, rarity, weight, tags, evaluated, {
		"shapeVocabulary": shape_vocabulary.duplicate(true),
		"liquidVocabulary": liquid_vocabulary.duplicate(true)
	})

static func append_skill(
	pool: SpaceRoguelikeIndividualPool,
	definition: SpaceSkillDefinition,
	benefit_metrics: Dictionary,
	balance_context: Dictionary,
	balance_profile: SpaceSkillBalanceProfile,
	rarity: String,
	weight: float,
	tags: Array = [],
	jar_world_options: Dictionary = {}
) -> Dictionary:
	if pool == null or pool.item_kind != "skill":
		return _failure("skill entry requires a skill pool")
	var evaluated := SpaceIndividualPowerEvaluator.evaluate_skill(
		definition, benefit_metrics, balance_context, balance_profile, pool.power_model, jar_world_options
	)
	if not bool(evaluated.get("success", false)):
		return evaluated
	var provenance := {
		"benefitMetrics": benefit_metrics.duplicate(true),
		"balanceContext": balance_context.duplicate(true)
	}
	if definition.jar_order_template_id != &"":
		if String(jar_world_options.get("orderTemplates", []).size()) == "0":
			return _failure("template-backed skill pool entry requires the exact Core world orderTemplates")
		provenance["orderTemplateName"] = definition.core_order_template_name()
	return _append(pool, definition.skill_id, definition.definition_version, rarity, weight, tags, evaluated, provenance)

static func _append(
	pool: SpaceRoguelikeIndividualPool,
	definition_id: StringName,
	version: int,
	rarity: String,
	weight: float,
	tags: Array,
	evaluated: Dictionary,
	provenance: Dictionary
) -> Dictionary:
	if pool == null or not bool(evaluated.get("success", false)) or definition_id == &"" or version <= 0 or not is_finite(weight) or weight <= 0.0 or not (tags is Array):
		return _failure("pool entry identity, evaluation, weight or tags are invalid")
	if not pool.power_bands.has(rarity) or not (pool.power_bands[rarity] is Dictionary):
		return _failure("entry rarity has no authored power budget")
	var band: Dictionary = pool.power_bands[rarity]
	var score := float(evaluated.get("powerScore", -1.0))
	if score < float(band.get("minimum", INF)) or score > float(band.get("maximum", -INF)):
		return _failure("evaluated definition power is outside the selected rarity budget")
	for existing in pool.entries:
		if String(existing.get("definitionId", "")) == String(definition_id) and int(existing.get("definitionVersion", 0)) == version:
			return _failure("exact definition version already exists in this pool")
	var entry := {
		"definitionId": String(definition_id),
		"definitionVersion": version,
		"rarity": rarity,
		"powerScore": score,
		"powerMetrics": evaluated.powerMetrics.duplicate(true),
		"weight": weight,
		"tags": tags.duplicate(true)
	}
	for key in provenance:
		entry[key] = provenance[key].duplicate(true) if provenance[key] is Dictionary or provenance[key] is Array else provenance[key]
	pool.entries.append(entry)
	var errors := pool.get_validation_errors()
	if not errors.is_empty():
		pool.entries.pop_back()
		return _failure("; ".join(errors))
	return {"success": true, "entry": entry.duplicate(true), "powerScore": score}

static func _failure(reason: String) -> Dictionary:
	return {"success": false, "reason": reason}
