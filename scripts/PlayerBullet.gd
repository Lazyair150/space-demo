extends Area2D

@export var speed:float =900
@export var damage:int=1
@export var lifetime:float=1.2

# 穿透次数：0 = 击中即消失（默认），1 = 击中一个目标后继续飞
@export var pierce_count:int = 0
## 谁打出的这一发（给伤害上下文用，可为空）
@export var attacker: Node

var _time_alive:float=0.0
var _hits_used:int=0
var _hit_ids:Dictionary={}

func _ready() -> void:
	add_to_group("player_bullet")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
func _on_body_entered(body:Node)->void:
	_consume_hit(body)

func _on_area_entered(area:Area2D)->void:
	_consume_hit(area)

# 同一个目标只吃一次伤害；穿透次数用尽才消失
func _consume_hit(node:Node)->void:
	if _hit_ids.has(node.get_instance_id()):
		return
	_hit_ids[node.get_instance_id()]=true
	_try_hit(node)
	if _hits_used >= pierce_count:
		queue_free()
	else:
		_hits_used+=1

func _try_hit(node:Node)->void:
	var info := DamageInfo.make(damage, &"bullet", attacker, self, global_position)
	if node.has_method("receive_damage"):
		node.receive_damage(info)
	elif node.has_method("take_damage"):
		node.take_damage(damage)
	

#主动逻辑
func _physics_process(delta: float) -> void:
	position+=Vector2.RIGHT.rotated(rotation)*speed*delta
	_time_alive+=delta
	if _time_alive>=lifetime:
		queue_free()


	
