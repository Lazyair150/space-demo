extends CharacterBody2D

signal died
signal damaged

const EXPLOSION_SCENE:=preload("res://scenes/actors/Explosion.tscn")

@export var speed:float=320
@export var accel:float=1800
@export var friction:float=1500
@export var max_hp:int=3
@export var invuln_time:float=0.6
@export var fire_rate:float =0.18
@export var bullet_scene:PackedScene


@onready var muzzle_flash: Sprite2D = $Muzzle/Flash
@onready var muzzle: Marker2D = $Muzzle
@onready var laser_sfx:AudioStreamPlayer2D=$LaserSFX
@onready var hit_sfx:AudioStreamPlayer2D=$HitSFX
@onready var sprite: Sprite2D = $Sprite2D

@onready var features:PlayerFeatures=$PlayerFeatures
@onready var stats:StatCalculator=$Stats
@onready var effects:StatusEffectManager=$Effects

var hp:int=3
var _invuln:float=0.0
var _shoot_cooldown:float=0.0

func _ready() -> void:
	hp=max_hp
	add_to_group("player")
	GameState.report_player_hp(hp)
	muzzle_flash.visible=false
	_load_sound(laser_sfx,["res://assets/audio/laser.ogg",
	"res://assets/audio/laser/wav"])
	_load_sound(hit_sfx,["res://assets/audio/hurt.ogg",
	"res://assets/audio/hurt/wav",
	"res://assets/audio/impact.ogg",
	"res://assets/audio/impact.wav"])
#主动处理以完成游戏交互

func _load_sound(player_node:AudioStreamPlayer2D,candidates:Array)->void:
	for p in candidates:
		if ResourceLoader.exists(p):
			player_node.stream=load(p)
			return


func _physics_process(delta: float) -> void:
	_invuln=max(0.0,_invuln-delta)
	#冷却递减
	_shoot_cooldown=maxf(0.0,_shoot_cooldown-delta)
	
	var input_dir:=Input.get_vector("move_left","move_right","move_up","move_down")
	if input_dir.length()>0.0:
		velocity=velocity.move_toward(input_dir*_stat_value(&"speed",speed),accel*delta)
	else:
		velocity=velocity.move_toward(Vector2.ZERO,friction*delta)
	move_and_slide()
	
	look_at(get_global_mouse_position())
	
	if Input.is_action_pressed("shoot") and _shoot_cooldown<=0.0:
		_shoot()
		_shoot_cooldown=_stat_value(&"fire_rate",fire_rate)
		
func take_damage(amount:int=1)->void:
	#无敌时间
	if _invuln>0.0:
		return
	# 先询问额外功能是否能够抵挡
	if features.try_block_damage(self,amount):
		return
	
	hp=max(0,hp-amount)
	GameState.report_player_hp(hp)
	_invuln=invuln_time
	damaged.emit()
	_flash_hit()
	if hit_sfx.stream:
		hit_sfx.play()
	if hp<=0:
		died.emit()
		_spawn_explosion()
		queue_free()

func _flash_hit()->void:
	var tween:=create_tween()
	sprite.modulate=Color(2.5,0.5,0.5,1.0)
	tween.tween_property(sprite,"modulate",Color.WHITE,invuln_time)
	
# 属性读取：基础值仍由 @export（或 GameState 的永久成长）提供，
# 临时修正由 Stats 汇总；这一层不做任何永久写入。
func _stat_value(stat:StringName,base:float)->float:
	if stats==null:
		return base
	return stats.value_of(stat,base)

# 施加一个临时状态效果（Buff/Debuff），返回实例；没有主管理器时返回 null
func grant_buff(definition:BuffDefinition,duration:float=-1.0)->BuffInstance:
	if effects==null:
		return null
	return effects.apply(definition,self,duration)

# 攻击力的两层：永久成长（GameState）→ 临时修正（Stats）
func attack_base()->int:
	var wallet:=get_node_or_null("/root/GameState")
	if wallet!=null and wallet.has_method("attack_damage"):
		return int(wallet.attack_damage())
	return 1

func attack_final()->float:
	return _stat_value(&"attack",float(attack_base()))

# 子弹伤害是整数：基础 1 点时 +50% 若直接截断仍是 1，等于 Buff 白吃。
# 所以这里做四舍五入，并把"取整"这件事收敛在这一个函数里。
func attack_damage_int()->int:
	return maxi(1, int(round(attack_final())))

func is_invulnerable()->bool:
	return _invuln>0.0

# 给能力用的无敌窗口（能量盾抵挡成功后调用），只延长不缩短。
func grant_invuln(seconds:float)->void:
	_invuln=maxf(_invuln,seconds)

func _shoot()->void:
	spawn_bullet()
	features.notify_attack(self)

func spawn_bullet()->void:
	if bullet_scene ==null:
		return
	var b:Node2D=bullet_scene.instantiate()
	# 子弹伤害读玩家钱包里的攻击力等级（工业舱产出的产品换来的强化材料提升它）。
	# 取不到 GameState 就用子弹自身的默认伤害，不让战斗因为工业侧缺席而崩。
	b.set("damage",attack_damage_int())
	# 先进树再定全局坐标：未入树时 global_position 等价于 position，
	# 一旦父节点不在原点，先设后加会落错位置。
	get_parent().add_child(b)
	b.global_position=muzzle.global_position
	b.rotation=rotation
	_flash_muzzle()
	if laser_sfx.stream:
		laser_sfx.pitch_scale=randf_range(0.95,1.08)
		laser_sfx.play()
		
func _flash_muzzle()->void:
	muzzle_flash.visible=true
	muzzle_flash.modulate=Color(1,1,1,1)
	var tween:=create_tween()
	tween.tween_property(muzzle_flash,"modulate:a",0.0,0.08)
	tween.tween_callback(func():muzzle_flash.visible=false)
	
func _spawn_explosion()->void:
	var e:Node2D=EXPLOSION_SCENE.instantiate()
	e.global_position=global_position
	get_parent().add_child(e)
		
