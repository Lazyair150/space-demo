extends Resource
class_name SpaceCampaignProgressState
## Durable campaign clear ledger. Reward application is a separate idempotent settlement transaction.

signal changed(revision: int)

const SCHEMA_VERSION := 1
@export var schema_version: int = SCHEMA_VERSION
@export var revision: int = 0
@export var cleared_stage_records: Array[Dictionary] = []
@export var reward_settlement_ids: PackedStringArray = PackedStringArray()

func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if schema_version != SCHEMA_VERSION or revision < 0:
		errors.append("campaign progress schema or revision is invalid")
	var stage_keys := {}
	var settlement_keys := {}
	for record in cleared_stage_records:
		if not (record is Dictionary):
			errors.append("campaign clear record must be a dictionary")
			continue
		var stage_id := String(record.get("stageId", ""))
		var version: Variant = record.get("definitionVersion", null)
		var settlement_id := String(record.get("rewardSettlementId", ""))
		var result: Variant = record.get("result", null)
		if stage_id.is_empty() or typeof(version) != TYPE_INT or int(version) <= 0 or settlement_id.is_empty() or not (result is Dictionary):
			errors.append("campaign clear record is missing exact stage identity, settlement identity, or result")
			continue
		var key := "%s@%d" % [stage_id, int(version)]
		if stage_keys.has(key):
			errors.append("campaign stage clear is duplicated: " + key)
		stage_keys[key] = true
		if settlement_keys.has(settlement_id):
			errors.append("campaign reward settlement is duplicated: " + settlement_id)
		settlement_keys[settlement_id] = true
	for settlement_id in reward_settlement_ids:
		if settlement_id.is_empty() or settlement_keys.has(String(settlement_id)):
			errors.append("campaign settlement ledger contains an empty or duplicate ID")
		settlement_keys[String(settlement_id)] = true
	return errors

func is_stage_cleared(stage_id: String, version: int) -> bool:
	for record in cleared_stage_records:
		if String(record.get("stageId", "")) == stage_id and int(record.get("definitionVersion", 0)) == version:
			return true
	return false

func cleared_stage_ids() -> Array:
	var result: Array = []
	for record in cleared_stage_records:
		var stage_id := String(record.get("stageId", ""))
		if not result.has(stage_id):
			result.append(stage_id)
	return result

func record_stage_clear(stage: SpaceStageDefinition, result: Dictionary, settlement_id: String) -> bool:
	if stage == null or not stage.is_valid() or settlement_id.strip_edges().is_empty() or result.is_empty():
		return false
	if not get_validation_errors().is_empty() or is_stage_cleared(String(stage.stage_id), stage.definition_version) or reward_settlement_ids.has(settlement_id):
		return false
	cleared_stage_records.append({
		"stageId": String(stage.stage_id),
		"definitionVersion": stage.definition_version,
		"campaignId": String(stage.campaign_id),
		"sequenceIndex": stage.sequence_index,
		"rewardSettlementId": settlement_id,
		"result": result.duplicate(true)
	})
	revision += 1
	changed.emit(revision)
	return true

func to_data() -> Dictionary:
	if not get_validation_errors().is_empty():
		return {}
	return {
		"schemaVersion": schema_version,
		"revision": revision,
		"clearedStageRecords": cleared_stage_records.duplicate(true),
		"rewardSettlementIds": Array(reward_settlement_ids)
	}

static func from_data(source: Dictionary) -> SpaceCampaignProgressState:
	if int(source.get("schemaVersion", 0)) != SCHEMA_VERSION:
		return null
	var records: Variant = source.get("clearedStageRecords", null)
	var settlements: Variant = source.get("rewardSettlementIds", null)
	if not (records is Array) or not (settlements is Array):
		return null
	var state := SpaceCampaignProgressState.new()
	state.schema_version = SCHEMA_VERSION
	state.revision = int(source.get("revision", -1))
	for record in records:
		if not (record is Dictionary):
			return null
		state.cleared_stage_records.append(record.duplicate(true))
	for settlement_id in settlements:
		if typeof(settlement_id) != TYPE_STRING:
			return null
		state.reward_settlement_ids.append(String(settlement_id))
	return state if state.get_validation_errors().is_empty() else null
