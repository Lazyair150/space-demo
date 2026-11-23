extends RefCounted
class_name SpaceRoguelikeIndividualRewardService
## Converts a validated weighted pool candidate into one independently owned instance.

static func acquire_candidate(
	state: SpacePlayerProgressionState,
	bundle: SpaceHangarCatalogBundle,
	library: SpaceRoguelikeIndividualLibrary,
	candidate: Dictionary,
	instance_id: String
) -> Dictionary:
	if state == null or bundle == null or library == null or instance_id.strip_edges().is_empty():
		return {"success": false, "reason": "reward acquisition dependencies are missing"}
	if not state.get_validation_errors().is_empty() or not bundle.validate_and_prepare().is_empty() or not library.is_valid():
		return {"success": false, "reason": "progression state, catalog bundle or individual library is invalid"}
	var item_kind := String(candidate.get("itemKind", ""))
	var pool := library.resolve_pool(item_kind, String(candidate.get("poolId", "")), int(candidate.get("poolVersion", 0)))
	if pool == null:
		return {"success": false, "reason": "candidate references an unknown exact pool version"}
	if String(candidate.get("powerModelId", "")) != String(pool.power_model_id) or int(candidate.get("powerModelVersion", 0)) != pool.power_model_version:
		return {"success": false, "reason": "candidate power model identity does not match the pool"}
	var definition_id := String(candidate.get("definitionId", ""))
	var definition_version := int(candidate.get("definitionVersion", 0))
	var rarity := String(candidate.get("rarity", ""))
	var power_score := float(candidate.get("powerScore", -1.0))
	if not pool.validate_effective_power(definition_id, definition_version, rarity, power_score).is_empty():
		return {"success": false, "reason": "candidate power score is outside its rarity budget"}
	if not SpacePlayerProgressionCatalogService.validate_definition(bundle, item_kind, definition_id, definition_version):
		return {"success": false, "reason": "candidate exact definition version is not present in the prepared catalog"}
	var instance := SpaceOwnedProgressionInstance.new()
	instance.instance_id = StringName(instance_id)
	instance.item_kind = item_kind
	instance.definition_id = StringName(definition_id)
	instance.definition_version = definition_version
	instance.level = 1
	instance.experience = 0
	instance.growth_attributes = {
		"roguelike": {
			"poolId": String(pool.pool_id),
			"poolVersion": pool.definition_version,
			"powerModelId": String(pool.power_model_id),
			"powerModelVersion": pool.power_model_version,
			"rarity": rarity,
			"basePowerScore": power_score
		}
	}
	if not state.unlock_and_acquire_instance(instance):
		return {"success": false, "reason": "progression aggregate rejected atomic unlock/acquisition"}
	return {
		"success": true,
		"instanceId": instance_id,
		"itemKind": item_kind,
		"definitionId": definition_id,
		"definitionVersion": definition_version,
		"rarity": rarity,
		"powerModelId": String(pool.power_model_id),
		"powerModelVersion": pool.power_model_version,
		"powerScore": power_score,
		"progressionRevision": state.state_revision
	}
