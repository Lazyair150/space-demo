extends RefCounted
class_name SpaceStageBossActorProbe
## Verifies the typed boss identity contract and stage encounter durability scaling.

static func run() -> bool:
	var scene := load("res://scenes/actors/SpaceStageBoss.tscn") as PackedScene
	if scene == null:
		return false
	var boss := scene.instantiate() as SpaceStageBossActor
	if boss == null or boss.max_hp != 24:
		if boss != null:
			boss.free()
		return false
	if not boss.configure_stage_boss("rift_warden", 1.4) or boss.boss_definition_id != &"rift_warden" or boss.max_hp != 34:
		boss.free()
		return false
	boss.free()
	var invalid := scene.instantiate() as SpaceStageBossActor
	if invalid == null:
		return false
	var accepted := invalid.configure_stage_boss("rift_warden", 0.0)
	invalid.free()
	return not accepted
