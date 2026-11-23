extends CharacterBody2D

const EXPLOSION_SCENE:=preload("res://scenes/actors/Explosion.tscn")

# 死亡事件：位置给掉落系统用
signal died(at:Vector2)

@export var max_hp :int =3
@export var fire_interval:float =1.5
@export var speed:float=110
@export var preferred_distance:float =320
@export var distance_tolerance:float =40.0
@export var bullet_scene:PackedScene
@export var score_value:int=25
## Versioned, optional finite energy-stone drop data. Null means this enemy drops no stone.
@export var energy_stone_drop_profile: SpaceEnergyStoneDropProfile

@onready var health:Health=$Health
@onready var receiver:DamageReceiver=$DamageReceiver

var hp:int:
	get:
		return health.current if health != null else 0
var _fire_cooldown:float=0.0

func _ready() -> void:
	add_to_group("enemies")
	health.set_max(max_hp, true)
	if not health.died.is_connected(_on_health_died):
		health.died.connect(_on_health_died)
	_fire_cooldown =randf_range(0.4,fire_interval)

func _physics_process(delta: float) -> void:
	_fire_cooldown=maxf(0.0,_fire_cooldown-delta)
	var player:=_find_player()
	if player ==null:
		return
	var to_player:=player.global_position-global_position
	var dist:=to_player.length()
	var dir:=to_player.normalized()
	look_at(player.global_position)
	
	if dist >preferred_distance+distance_tolerance:
		velocity=dir *speed
	elif dist<preferred_distance-distance_tolerance:
		velocity=-dir*speed
	else:
		# 注意：Vector2.move_toward 返回新值，不写回等于没减速
		velocity=velocity.move_toward(Vector2.ZERO,speed*2.0*delta)
		
	move_and_slide()
	
	if _fire_cooldown<=0.0 and bullet_scene !=null:
		_fire(dir)
		_fire_cooldown=fire_interval
		
func _find_player()->Node2D:
	var nodes:=get_tree().get_nodes_in_group("player")
	return nodes[0] if nodes.size()>0 else null

func _fire(dir:Vector2)->void:
	var b:Node2D =bullet_scene.instantiate()
	b.set("attacker", self)
	# 先入树再设全局坐标，父节点有非零变换时也不会偏
	get_parent().add_child(b)
	b.global_position=global_position+dir*32.0
	# dir 是世界方向，必须写 global_rotation；写 rotation 会被父节点旋转变换再偏一次
	b.global_rotation=dir.angle()

func take_damage(amount:int =1)->void:
	receive_damage(DamageInfo.make(amount,&"legacy"))

func receive_damage(info:DamageInfo)->DamageResult:
	var result := receiver.receive(info)
	CombatFx.show_damage(get_parent(), result)
	return result

func _on_health_died(_info:DamageInfo)->void:
	GameState.add_score(score_value)
	_spawn_explosion()
	died.emit(global_position)
	queue_free()

func _spawn_explosion()->void:
	var e:Node2D=EXPLOSION_SCENE.instantiate()
	e.global_position=global_position
	get_parent().add_child(e)
