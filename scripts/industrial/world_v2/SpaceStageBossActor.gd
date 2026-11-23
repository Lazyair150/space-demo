extends "res://scripts/EnemyChaser.gd"
class_name SpaceStageBossActor
## Typed finite-stage boss actor. Movement/damage reuse the enemy combat pipeline;
## the definition identity is explicit and reported to the stage objective runtime.

@export var boss_definition_id: StringName = &""

func configure_stage_boss(definition_id: String) -> bool:
	if is_inside_tree() or definition_id.strip_edges().is_empty():
		return false
	boss_definition_id = StringName(definition_id)
	return true
