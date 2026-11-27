extends RefCounted
class_name SpaceStageModelProbe
## Contract probe for finite campaign data, progression-aware recommendations and durable clear records.

class ProbeHealth extends Node:
	var current: float = 10.0

static func run() -> bool:
	if not SpaceStageBossActorProbe.run():
		return false
	var catalog := load("res://data/stages/campaign_01/catalog.tres") as SpaceStageCatalog
	if catalog == null or not catalog.get_validation_errors().is_empty():
		return false
	var stages := catalog.stages_for_campaign("rift_frontier")
	if stages.size() != 5:
		return false
	var first := stages[0]
	var second := stages[1]
	var ore_convoy := stages[2]
	var boss_stage := stages[4]
	if not catalog.is_unlocked(first, []) or catalog.is_unlocked(second, []):
		return false
	if String(ore_convoy.objective_parameters.get("resource_type", "")) != "energy_stone" or float(ore_convoy.objective_parameters.get("target_amount", 0.0)) <= 0.0:
		return false
	if String(boss_stage.objective_parameters.get("boss_definition_id", "")) != "rift_warden":
		return false
	if ore_convoy.wave_plan(3).get("segment", "") != "rest":
		return false
	if not ore_convoy.is_valid() or not boss_stage.is_valid():
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
	if progression.record_stage_clear(second, {"rank": "gold"}, "stage-clear:drift-perimeter:v1"):
		return false # Settlement identity cannot be reused across stages.
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

	var collect_objective := SpaceStageObjectiveRuntime.new()
	if not collect_objective.configure(ore_convoy):
		return false
	if collect_objective.record_resource("wrong_resource", 5.0):
		return false
	if collect_objective.record_resource("energy_stone", 2.0) == false or collect_objective.is_complete():
		return false
	if not collect_objective.record_resource("energy_stone", 3.0) or not collect_objective.is_complete():
		return false
	var objective_checkpoint := collect_objective.capture_state()
	var restored_objective := SpaceStageObjectiveRuntime.new()
	if not restored_objective.restore_state(ore_convoy, objective_checkpoint) or not restored_objective.is_complete():
		return false

	var boss_objective := SpaceStageObjectiveRuntime.new()
	if not boss_objective.configure(boss_stage) or boss_objective.record_boss_defeated("wrong_boss"):
		return false
	if not boss_objective.record_boss_defeated("rift_warden") or boss_objective.is_complete():
		return false
	if not boss_objective.mark_encounters_completed() or not boss_objective.is_complete():
		return false

	var protect_stage := SpaceStageDefinition.new()
	protect_stage.stage_id = &"probe.protect-target"
	protect_stage.definition_version = 1
	protect_stage.campaign_id = &"probe.campaign"
	protect_stage.display_name = "Protect Target Probe"
	protect_stage.objective = "protect_target"
	protect_stage.objective_parameters = {"target_definition_id": "probe.relay"}
	protect_stage.wave_plans = [{"segment": "warmup", "chaser_count": 1, "shooter_count": 0, "elite_count": 0, "break_seconds": 0.0}]
	var protected_target := Node.new()
	var protected_health := ProbeHealth.new()
	protected_health.name = "Health"
	protected_target.add_child(protected_health)
	var protect_objective := SpaceStageObjectiveRuntime.new()
	if not protect_objective.configure(protect_stage, protected_target):
		protected_target.free()
		return false
	protected_health.current = 0.0
	if not protect_objective.advance(0.016) or not protect_objective.is_failed() or protect_objective.is_complete():
		protected_target.free()
		return false
	var failed_checkpoint := protect_objective.capture_state()
	var failed_restore := SpaceStageObjectiveRuntime.new()
	if failed_restore.restore_state(protect_stage, failed_checkpoint, protected_target):
		protected_target.free()
		return false
	protected_target.free()

	var director := SpaceStageEncounterDirector.new()
	if not director.configure(first, loadout):
		return false
	var first_beat := director.begin()
	if first_beat.is_empty() or int(first_beat.beatIndex) != 0:
		return false
	var beat_result := director.complete_current_beat()
	if not bool(beat_result.get("success", false)) or bool(beat_result.get("complete", true)):
		return false
	var director_checkpoint := director.capture_state()
	var resumed_director := SpaceStageEncounterDirector.new()
	if not resumed_director.restore_state(first, loadout, director_checkpoint):
		return false
	if int(resumed_director.current_beat().beatIndex) != 1:
		return false
	return true
