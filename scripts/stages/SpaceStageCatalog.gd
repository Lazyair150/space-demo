extends Resource
class_name SpaceStageCatalog
## Version-exact stage registry. Unlock policy is explicit and independent from combat scaling.

@export var definitions: Array[SpaceStageDefinition] = []

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var identities := {}
	var campaign_positions := {}
	for definition in definitions:
		if definition == null:
			errors.append("stage catalog contains a null definition")
			continue
		errors.append_array(definition.get_validation_errors())
		var key := "%s@%d" % [String(definition.stage_id), definition.definition_version]
		if identities.has(key):
			errors.append("duplicate stage identity/version: " + key)
		identities[key] = true
		var position_key := "%s:%d" % [String(definition.campaign_id), definition.sequence_index]
		if campaign_positions.has(position_key):
			errors.append("duplicate stage position in campaign: " + position_key)
		campaign_positions[position_key] = true
	return errors

func resolve_stage(stage_id: String, version: int) -> SpaceStageDefinition:
	for definition in definitions:
		if definition != null and String(definition.stage_id) == stage_id and definition.definition_version == version and definition.is_valid():
			return definition
	return null

func stages_for_campaign(campaign_id: String) -> Array[SpaceStageDefinition]:
	var result: Array[SpaceStageDefinition] = []
	for definition in definitions:
		if definition != null and String(definition.campaign_id) == campaign_id and definition.is_valid():
			result.append(definition)
	result.sort_custom(func(a: SpaceStageDefinition, b: SpaceStageDefinition) -> bool: return a.sequence_index < b.sequence_index)
	return result

func is_unlocked(stage: SpaceStageDefinition, cleared_stage_keys: Array) -> bool:
	if stage == null or not stage.is_valid():
		return false
	if stage.sequence_index == 1:
		return true
	for previous in stages_for_campaign(String(stage.campaign_id)):
		if previous.sequence_index == stage.sequence_index - 1:
			return cleared_stage_keys.has("%s@%d" % [String(previous.stage_id), previous.definition_version])
	return false
