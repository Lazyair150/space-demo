extends StaticBody2D

const EXPLOSION_SCENE := preload("res://scenes/actors/Explosion.tscn")
@export var max_hp: int = 2
@export var score_value: int = 5

var hp: int = 0

func _ready() -> void:
	hp = max_hp

func take_damage(amount: int = 1) -> void:
	hp -= amount
	if hp <= 0:
		GameState.add_score(score_value)
		_spawn_explosion()
		queue_free()

func _spawn_explosion() -> void:
	var explosion: Node2D = EXPLOSION_SCENE.instantiate()
	explosion.global_position = global_position
	get_parent().add_child(explosion)
