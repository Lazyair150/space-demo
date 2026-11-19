extends CharacterBody2D

const EXPLOSION_SCENE:=preload("res://scenes/actors/Explosion.tscn")

# 死亡事件：位置给掉落系统用，敌人自己不知道会掉什么
signal died(at:Vector2)

@export var speed:float=130
@export var max_hp:int=2
@export var contact_damage:int =1
@export var score_value:int=10
## 出生时挂几层通用次数护盾（0 = 不挂）。留给"精英/带盾变体"用，默认不变强。
@export var starting_shield: int = 0

@onready var health:Health=$Health
@onready var receiver:DamageReceiver=$DamageReceiver

# 兼容旧读取点：血量统一由 Health 持有
var hp:int:
	get:
		return health.current if health != null else 0


func _ready() -> void:
	add_to_group("enemies")
	health.set_max(max_hp, true)
	if not health.died.is_connected(_on_health_died):
		health.died.connect(_on_health_died)
	if starting_shield > 0:
		_attach_shield(starting_shield)

func _physics_process(delta: float) -> void:
	var player:=_find_player()
	if player ==null:
		return
	var dir :=(player.global_position-global_position).normalized()
	velocity =dir *speed
	look_at(player.global_position)
	var col:=move_and_collide(velocity*delta)
	if col:
		var other:=col.get_collider()
		if other and other.is_in_group("player"):
			var info := DamageInfo.make(contact_damage, &"contact", self, self, global_position)
			if other.has_method("receive_damage"):
				other.receive_damage(info)
			elif other.has_method("take_damage"):
				other.take_damage(contact_damage)
			#_spawn_explosion()角色自己处理死亡和受击音效
			died.emit(global_position)
			queue_free()
			
func _find_player()->Node2D:
	var nodes:=get_tree().get_nodes_in_group("player")
	return nodes[0] if nodes.size()>0 else null

func _spawn_explosion()->void:
	var e:Node2D=EXPLOSION_SCENE.instantiate()
	e.global_position=global_position
	get_parent().add_child(e)

# 复用通用防御组件：不复制玩家的 ShieldDefense，也不需要 PlayerFeatures
func _attach_shield(charges: int) -> void:
	var shield := ShieldCharges.new()
	shield.name = "ShieldCharges"
	shield.charges = charges
	add_child(shield)
	if receiver != null and not receiver.defenses.has(shield):
		receiver.defenses.append(shield)

## 旧接口：迁移期适配器
func take_damage(amount:int =1)->void:
	receive_damage(DamageInfo.make(amount,&"legacy"))

## 新接口：交给受击管线结算，并给出飘字表现
func receive_damage(info:DamageInfo)->DamageResult:
	var result := receiver.receive(info)
	CombatFx.show_damage(get_parent(), result)
	return result

# 死亡只在这里发生：计分、爆炸、通知掉落、移除
func _on_health_died(_info:DamageInfo)->void:
	GameState.add_score(score_value)
	_spawn_explosion()
	died.emit(global_position)
	queue_free()
