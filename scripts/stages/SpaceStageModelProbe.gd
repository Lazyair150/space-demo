extends RefCounted
class_name SpaceStageModelProbe
## Contract probe for finite campaign data, progression-aware recommendations and durable clear records.

static func run() -> bool:
	var catalog := load("res://data/stages/campaign_01/catalog.tres") as SpaceStageCatalog
	if catalog == null or not catalog.get_validation_errors().is_empty():
		return false
	var stages := catalog.stages_for_campaign("rift_frontier")
	if stages.size() != 5:
		return false
	var first := stages[0]
	var second := stages[1]
	if not catalog.is_unlocked(first, []) or catalog.is_unlocked(second, []):
		return false

	var progression := SpaceCampaignProgressState.new()
	if not progression.record_stage_clear(first, {"rank": "bronze", "elapsedSeconds": 120}, "stage-clear:drift-perimeter:v1"):
		return false
	if not progression.is_stage_cleared(String(first.stage_id), first.definition_version):
		return false
	if progression.record_stage_clear(first, {"rank": "gold"}, "stage-clear:duplicate"):
		return false
	if not catalog.is_unlocked(second, progression.cleared_stage_keys()):
		return false
	var restored := SpaceCampaignProgressState.from_data(progression.to_data())
	if restored == null or not restored.is_stage_cleared(String(first.stage_id), first.definition_version):
		return false

	var loadout := {
		"ownedInstanceSnapshots": [
			{"instanceId": "ship-a", "level": 2},
			{"instanceId": "parser-a", "level": 4},
			{"instanceId": "skill-a", "level": 3}
		]
	}
	var difficulty := SpaceStageProgressionProfile.evaluate(first, loadout)
	if not bool(difficulty.get("valid", false)):
		return false
	if absf(float(difficulty.averageLoadoutLevel) - 3.0) > 0.000001:
		return false
	if absf(float(difficulty.encounterScale) - 1.16) > 0.000001:
		return false
	return true
