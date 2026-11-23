extends "res://scripts/EnemyChaser.gd"
class_name SpaceStageBossActor
## Typed finite-stage boss actor. Movement/damage reuse the enemy combat pipeline;
## the definition identity is explicit and reported to the stage objective runtime.

@export var boss_definition_id: StringName = &""
var applied_encounter_scale: float = 1.0

func configure_stage_boss(definition_id: String, encounter_scale: float = 1.0) -> bool:
	if is_inside_tree() or definition_id.strip_edges().is_empty() or not is_finite(encounter_scale) or encounter_scale <= 0.0:
		return false
	boss_definition_id = StringName(definition_id)
	applied_encounter_scale = encounter_scale
	max_hp = maxi(1, int(ceil(float(max_hp) * encounter_scale)))
	return true

var _contact_damage_cooldown: float = 0.0

func _physics_process(delta: float) -> void:
	_contact_damage_cooldown = maxf(0.0, _contact_damage_cooldown - delta)
	var player := _find_player()
	if player == null:
		return
	var direction := (player.global_position - global_position).normalized()
	velocity = direction * speed
	look_at(player.global_position)
	var collision := move_and_collide(velocity * delta)
	if collision == null:
		return
	var other := collision.get_collider()
	if other != null and other.is_in_group("player") and _contact_damage_cooldown <= 0.0:
		var info := DamageInfo.make(contact_damage, &"contact", self, self, global_position)
		if other.has_method("receive_damage"):
			other.receive_damage(info)
		elif other.has_method("take_damage"):
			other.take_damage(contact_damage)
		_contact_damage_cooldown = 0.8
