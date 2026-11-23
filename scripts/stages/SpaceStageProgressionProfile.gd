extends RefCounted
class_name SpaceStageProgressionProfile
## Compares a frozen loadout with authored stage expectations. It does not mutate player growth.

static func average_loadout_level(loadout_data: Dictionary) -> float:
	var snapshots: Variant = loadout_data.get("ownedInstanceSnapshots", null)
	if not (snapshots is Array) or snapshots.is_empty():
		return 0.0
	var total := 0.0
	var count := 0
	for raw in snapshots:
		if not (raw is Dictionary):
			return 0.0
		var level: Variant = raw.get("level", null)
		if typeof(level) != TYPE_INT or int(level) < 1:
			return 0.0
		total += float(level)
		count += 1
	return total / float(count) if count > 0 else 0.0

static func evaluate(stage: SpaceStageDefinition, loadout_data: Dictionary) -> Dictionary:
	if stage == null or not stage.is_valid():
		return {}
	var level := average_loadout_level(loadout_data)
	if level <= 0.0:
		return {"valid": false, "reason": "battle loadout has no frozen owned progression instances"}
	var delta := level - float(stage.recommended_loadout_level)
	var tuning := stage.difficulty_profile
	var under_tuned_penalty := float(tuning.get("under_level_assistance_per_level", 0.0))
	var over_level_pressure := float(tuning.get("over_level_pressure_per_level", 0.0))
	var minimum := float(tuning.get("minimum_encounter_scale", 1.0))
	var maximum := float(tuning.get("maximum_encounter_scale", 1.0))
	if under_tuned_penalty < 0.0 or over_level_pressure < 0.0 or minimum <= 0.0 or maximum < minimum:
		return {"valid": false, "reason": "stage difficulty profile is invalid"}
	var scale := 1.0
	if delta < 0.0:
		scale = maxf(minimum, 1.0 - absf(delta) * under_tuned_penalty)
	elif delta > 0.0:
		scale = minf(maximum, 1.0 + delta * over_level_pressure)
	return {
		"valid": true,
		"averageLoadoutLevel": level,
		"recommendedLoadoutLevel": stage.recommended_loadout_level,
		"levelDelta": delta,
		"encounterScale": scale,
		"tuningAuthoredByStage": true
	}
