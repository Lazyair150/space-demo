extends Node
## 波次编排：热身 → 压力 → 精英 → 喘息，四波一循环。
## 依据 docs/design/07-tiny-wizard-对照与改造.md §3.2-A：把无限曲线切成有名字的段落，
## 每段只回答一个问题——热身教走位，压力考清怪效率，精英考爆发与闪避，喘息留整理窗口。

signal wave_cleared

const SEGMENT_WARMUP := 0
const SEGMENT_PRESSURE := 1
const SEGMENT_ELITE := 2
const SEGMENT_REST := 3
const SEGMENT_LABELS := ["热身", "压力", "精英", "喘息"]
## 喘息段额外给的整理时间（秒）。
const REST_BREAK_SECONDS := 4.0
## 精英机：血量随循环数递增（3、5、7…），移动更慢、体型更大、分数更高。
const ELITE_BASE_HP := 3
const ELITE_HP_PER_CYCLE := 2
const ELITE_SPEED := 92.0
const ELITE_SCALE := 1.45
const ELITE_SCORE := 60

@export var shooter_scene:PackedScene
@export var chaser_scene:PackedScene
@export var arena_rect:Rect2 =Rect2(80,80,1120,560)
@export var spawn_stagger_seconds:float=0.35
@export var wave_break_seconds:float=2.0
@export var pickup_scene:PackedScene
## 敌人死亡掉胶囊的概率（0 关掉）
@export var pickup_chance:float=0.25
## 可掉的 Buff 定义；留空则不掉
@export var pickup_effects:Array[BuffDefinition]=[]

var _current_wave:int=0
var _spawning:bool=false
var _alive_enemies:int=0
var _segment_index:int=SEGMENT_WARMUP
var _cycle:int=0
var _energy_stone_rng := RandomNumberGenerator.new()

func _ready()->void:
	_energy_stone_rng.randomize()
	await get_tree().process_frame
	_start_next_wave()

## 第 1 波热身、第 2 波压力、第 3 波精英、第 4 波喘息，第 5 波回到热身。
func segment_for_wave(wave:int)->int:
	return (wave - 1) % SEGMENT_LABELS.size()

func cycle_for_wave(wave:int)->int:
	return int(float(wave - 1) / float(SEGMENT_LABELS.size()))

func current_segment_label()->String:
	return SEGMENT_LABELS[_segment_index]

func current_segment()->int:
	return _segment_index

func _start_next_wave()->void:
	_current_wave +=1
	_segment_index =segment_for_wave(_current_wave)
	_cycle =cycle_for_wave(_current_wave)
	GameState.set_wave(_current_wave)
	GameState.set_segment(current_segment_label())
	var count :=0
	var shooter_chance :=0.0
	var elite :=false
	match _segment_index:
		SEGMENT_WARMUP:
			count =1 + _cycle
		SEGMENT_PRESSURE:
			count =2 + _cycle * 2
			shooter_chance =0.35
		SEGMENT_ELITE:
			count =1 + _cycle
			elite =true
		_:
			count =0
	_spawning=true
	for i in count:
		_spawn_one(shooter_chance, elite)
		await get_tree().create_timer(spawn_stagger_seconds).timeout
	_spawning=false
	_check_wave_clear()

func _spawn_one(shooter_chance:float, elite:bool)->void:
	var use_shooter :=(not elite) and shooter_scene != null and randf()<shooter_chance
	var scene:=shooter_scene if use_shooter else chaser_scene
	if scene == null:
		return
	var e:Node2D=scene.instantiate()
	if elite:
		e.set("max_hp", ELITE_BASE_HP + ELITE_HP_PER_CYCLE * _cycle)
		e.set("speed", ELITE_SPEED)
		e.set("score_value", ELITE_SCORE)
		e.scale =Vector2(ELITE_SCALE, ELITE_SCALE)
	e.position =_random_edge_position()
	e.tree_exited.connect(_on_enemy_freed)
	e.died.connect(_on_enemy_died_with_source.bind(e))
	get_parent().get_node("Arena").add_child(e)
	_alive_enemies+=1

func _random_edge_position()->Vector2:
	var edge:=randi()%4
	match edge:
		0:return Vector2(arena_rect.position.x+randf()*arena_rect.size.x,arena_rect.position.y-20)
		1:return Vector2(arena_rect.position.x+randf()*arena_rect.size.x,arena_rect.position.y+20)
		2:return Vector2(arena_rect.position.x-20,arena_rect.position.y+randf()*arena_rect.size.y)
		_:return Vector2(arena_rect.position.x+20,arena_rect.position.y+randf()*arena_rect.size.y)

func _on_enemy_died(at:Vector2)->void:
	if pickup_scene == null or pickup_effects.is_empty():
		return
	if randf() > pickup_chance:
		return
	var arena := get_parent().get_node_or_null("Arena")
	if arena == null:
		return
	var pickup := pickup_scene.instantiate()
	pickup.set("buff_definition", pickup_effects[randi() % pickup_effects.size()])
	pickup.set("tint", _pickup_tint(pickup.get("buff_definition")))
	pickup.position = at
	arena.add_child(pickup)

## Enemy death is a single event, but Buff capsules and energy stones are independent
## resource channels. Absence of one channel must never suppress the other.
func _on_enemy_died_with_source(at: Vector2, enemy: Node2D) -> void:
	_on_enemy_died(at)
	_spawn_energy_stone_pickup(at, enemy)

func _spawn_energy_stone_pickup(at: Vector2, enemy: Node2D) -> void:
	if enemy == null:
		return
	var profile: Variant = enemy.get("energy_stone_drop_profile")
	if not (profile is SpaceEnergyStoneDropProfile):
		return
	var game := get_parent()
	if game == null or not game.has_method("spawn_energy_stone_drop"):
		return
	var result: Dictionary = game.call("spawn_energy_stone_drop", profile, at, _energy_stone_rng)
	if not bool(result.get("success", false)):
		push_error("[Spawner] Energy-stone drop failed: " + String(result.get("reason", "")))

## 胶囊染色：按定义 id 取色，避免每个 Buff 都要一份美术资源
func _pickup_tint(definition)->Color:
	var id := String(definition.id) if definition != null else ""
	match id:
		"haste": return Color(0.55, 0.9, 1.0)
		"attack_boost": return Color(1.0, 0.72, 0.42)
		"poison": return Color(0.62, 0.9, 0.55)
		"aim_assist": return Color(0.98, 0.95, 0.62)
		"lifesteal": return Color(0.92, 0.55, 0.72)
		_: return Color(0.85, 0.85, 0.9)

func _on_enemy_freed()->void:
	_alive_enemies-=1
	if not is_inside_tree():
		return
	_check_wave_clear()

func _check_wave_clear()->void:
	if _spawning or _alive_enemies>0:
		return
	if not is_inside_tree():
		return
	wave_cleared.emit()
	await get_tree().create_timer(_break_seconds()).timeout
	if not is_inside_tree():
		return
	_start_next_wave()

## 喘息段多留两秒：玩家用这段时间决定去哪、要不要去工业舱。
func _break_seconds()->float:
	return REST_BREAK_SECONDS if _segment_index == SEGMENT_REST else wave_break_seconds
