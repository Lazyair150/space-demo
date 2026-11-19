extends Area2D

@export var speed:float =900
@export var damage:int=1
@export var lifetime:float=1.2

# 穿透次数：0 = 击中即消失（默认），1 = 击中一个目标后继续飞
@export var pierce_count:int = 0
## 谁打出的这一发（给伤害上下文用，可为空）
@export var attacker: Node
## 这一发是否暴击（由攻击方在生成子弹时判定）
@export var critical: bool = false

var _time_alive:float=0.0
var _hits_used:int=0
var _hit_ids:Dictionary={}

func _ready() -> void:
	add_to_group("player_bullet")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
func _on_body_entered(body)->void:
	_consume_hit(body)

func _on_area_entered(area)->void:
	_consume_hit(area)

# 同一个目标只吃一次伤害；穿透次数用尽才消失
func _consume_hit(node)->void:
	# 碰撞信号到达时目标可能已经被释放（同帧被别的伤害打死）。
	# 参数不标类型：标了 Node 的话，已释放实例在调用处就会抛类型错误，守卫根本进不来。
	if not is_instance_valid(node):
		return
	if _hit_ids.has(node.get_instance_id()):
		return
	_hit_ids[node.get_instance_id()]=true
	_try_hit(node)
	if _hits_used >= pierce_count:
		queue_free()
	else:
		_hits_used+=1

func _try_hit(node)->void:
	if not is_instance_valid(node):
		return
	# 攻击者可能已经被释放（例如开枪后玩家阵亡），这里先降级成"无攻击者"
	var who: Node = null
	if attacker != null and is_instance_valid(attacker):
		who = attacker
	var info := DamageInfo.make(damage, &"bullet", who, self, global_position, critical)
	var result: DamageResult = null
	if node.has_method("receive_damage"):
		result = node.receive_damage(info)
	elif node.has_method("take_damage"):
		result = node.take_damage(damage)
	# 结算结果回传给攻击者：吸血、反伤、命中特效都挂在这里，而不是各自去翻目标血量
	if result != null and who != null and who.has_method("on_damage_dealt"):
		who.on_damage_dealt(result)
	

#主动逻辑
func _physics_process(delta: float) -> void:
	position+=Vector2.RIGHT.rotated(rotation)*speed*delta
	_time_alive+=delta
	if _time_alive>=lifetime:
		queue_free()


	
