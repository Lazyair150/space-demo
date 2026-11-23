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
## 暴击率与倍率：数值本体在 Stats 里（方便 Buff 临时改），这两项是基础值
@export var crit_chance_base:float = 0.0
@export var crit_multiplier:float = 2.0
## 吸血比例：按"实际造成的 HP 伤害"回血，护盾/无敌挡下的部分不算
@export var lifesteal_base:float = 0.0
@export var bullet_scene:PackedScene


@onready var muzzle_flash: Sprite2D = $Muzzle/Flash
@onready var muzzle: Marker2D = $Muzzle
@onready var laser_sfx:AudioStreamPlayer2D=$LaserSFX
@onready var hit_sfx:AudioStreamPlayer2D=$HitSFX
@onready var sprite: Sprite2D = $Sprite2D

@onready var features:PlayerFeatures=$PlayerFeatures
@onready var stats:StatCalculator=$Stats
@onready var effects:StatusEffectManager=$Effects

# 生命与受伤管线：血量归 Health，受伤入口归 DamageReceiver，无敌归 Invulnerability
@onready var health:Health=$Health
@onready var invuln:Invulnerability=$Invulnerability
@onready var receiver:DamageReceiver=$DamageReceiver

# 兼容旧读取点：hp / _invuln 改成指向组件的读写代理，测试与能力脚本不用改。
var hp:int:
	get:
		return health.current if health != null else 0
var _invuln:float:
	get:
		return invuln.remaining if invuln != null else 0.0
	set(value):
		if invuln != null:
			invuln.remaining = maxf(0.0, value)
var _shoot_cooldown:float=0.0

func _ready() -> void:
	health.set_max(max_hp, true)
	if not health.health_changed.is_connected(_on_health_changed):
		health.health_changed.connect(_on_health_changed)
	if not health.died.is_connected(_on_health_died):
		health.died.connect(_on_health_died)
	add_to_group("player")
	GameState.report_player_hp(health.current)
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
		
## 旧接口：迁移期的薄适配器，行为与新接口完全一致
func take_damage(amount:int=1)->void:
	receive_damage(DamageInfo.make(amount,&"legacy"))

## 新接口：攻击方描述一次攻击，这里交给管线结算并负责表现反馈
func receive_damage(info:DamageInfo)->DamageResult:
	var result := receiver.receive(info)
	if result.hp_damage > 0:
		# 只在实际掉血后才进入无敌，被盾挡下不吃无敌帧（与改造前一致）
		invuln.start(invuln_time)
		damaged.emit()
		_flash_hit()
		if hit_sfx.stream:
			hit_sfx.play()
	CombatFx.show_damage(get_parent(), result)
	return result

func _on_health_changed(current:int, _max_value:int)->void:
	GameState.report_player_hp(current)

func _on_health_died(_info:DamageInfo)->void:
	# 人死了身上不该留着临时状态：撤掉所有 Buff 的修正器，避免影响下一局
	if effects != null:
		effects.clear_all()
	died.emit()
	_spawn_explosion()
	queue_free()

func _flash_hit()->void:
	var tween:=create_tween()
	sprite.modulate=Color(2.5,0.5,0.5,1.0)
	tween.tween_property(sprite,"modulate",Color.WHITE,invuln_time)
	
# Attribute reads combine the ship baseline with temporary Space effect modifiers.
func _stat_value(stat:StringName,base:float)->float:
	if stats==null:
		return base
	return stats.value_of(stat,base)

# 施加一个临时状态效果（Buff/Debuff），返回实例；没有主管理器时返回 null
func grant_buff(definition:BuffDefinition,duration:float=-1.0)->BuffInstance:
	if effects==null:
		return null
	return effects.apply(definition,self,duration)

# Base weapon damage is currently one point. Future permanent weapon profiles belong to Space ship/loadout data.
func attack_base() -> int:
	return 1

func attack_final()->float:
	return _stat_value(&"attack",float(attack_base()))

# 子弹伤害是整数：基础 1 点时 +50% 若直接截断仍是 1，等于 Buff 白吃。
# 所以这里做四舍五入，并把"取整"这件事收敛在这一个函数里。
func attack_damage_int()->int:
	return maxi(1, int(round(attack_final())))

func crit_multiplier_final()->float:
	return maxf(1.0, _stat_value(&"crit_multiplier", crit_multiplier))

func crit_chance()->float:
	return clampf(_stat_value(&"crit_chance", crit_chance_base), 0.0, 1.0)

func lifesteal_ratio()->float:
	return maxf(0.0, _stat_value(&"lifesteal", lifesteal_base))

## 攻击方判定暴击：请求在生成子弹时就定下来，进管线后不再改
func roll_damage()->Dictionary:
	var base := attack_damage_int()
	var is_crit := crit_chance() > 0.0 and randf() < crit_chance()
	var amount := int(round(float(base) * crit_multiplier_final())) if is_crit else base
	return {"amount": maxi(1, amount), "critical": is_crit}

## 造成实际伤害后由载体回调（吸血挂在这里，读的是结算结果而不是请求值）
func on_damage_dealt(result:DamageResult)->void:
	if result == null or result.hp_damage <= 0:
		return
	var ratio := lifesteal_ratio()
	if ratio <= 0.0:
		return
	var heal_amount := int(round(float(result.hp_damage) * ratio))
	if heal_amount > 0:
		health.heal(heal_amount)

func is_invulnerable()->bool:
	return invuln != null and invuln.is_active()

# 给能力用的无敌窗口（能量盾抵挡成功后调用），只延长不缩短。
func grant_invuln(seconds:float)->void:
	if invuln != null:
		invuln.start(seconds)

func _shoot()->void:
	spawn_bullet()
	features.notify_attack(self)

func spawn_bullet()->void:
	if bullet_scene ==null:
		return
	var b:Node2D=bullet_scene.instantiate()
	# Resolve damage from the Space weapon baseline plus currently active Space effect modifiers.
	var roll := roll_damage()
	b.set("damage", int(roll["amount"]))
	b.set("critical", bool(roll["critical"]))
	b.set("attacker",self)
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
		
