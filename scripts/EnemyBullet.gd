extends Area2D

@export var speed:float=380
@export var lifetime:float=2.2
@export var damage:int=1
@export var attacker: Node

var _time_alive:float=0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _on_body_entered(body:Node)->void:
	if body.is_in_group("player"):
		var info := DamageInfo.make(damage, &"bullet", attacker, self, global_position)
		if body.has_method("receive_damage"):
			body.receive_damage(info)
		elif body.has_method("take_damage"):
			body.take_damage(damage)
	queue_free()

func _on_area_entered(_area:Area2D)->void:
	queue_free()
	
func _physics_process(delta: float) -> void:
	position+=Vector2.RIGHT.rotated(rotation)*speed*delta
	_time_alive+=delta
	if _time_alive>=lifetime:
		queue_free()
	
