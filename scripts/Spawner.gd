extends Node
## 波次编排：热身 → 压力 → 精英 → 喘息，四波一循环。
## 依据 docs/design/07-tiny-wizard-对照与改造.md §3.2-A：把无限曲线切成有名字的段落，
## 每段只回答一个问题——热身教走位，压力考清怪效率，精英考爆发与闪避，喘息留整理窗口。

signal wave_cleared
signal encounters_completed(result: Dictionary)
signal stage_faulted(reason: String)

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
@export var boss_scene: PackedScene
@export var arena_rect:Rect2 =Rect2(80,80,1120,560)
@export var spawn_stagger_seconds:float=0.35
@export var wave_break_seconds:float=2.0
@export var pickup_scene:PackedScene
## 敌人死亡掉胶囊的概率（0 关掉）
@export var pickup_chance:float=0.25
## 可掉的 Buff 定义；留空则不掉
@export var pickup_effects:Array[BuffDefinition]=[]
## Optional elite-only profile. Its authored stone volumes can differ from ordinary enemies;
## null leaves the enemy scene's own optional profile unchanged.
## Prototype/demo encounter supply; null leaves ordinary enemies without stone drops.
@export var energy_stone_drop_profile: SpaceEnergyStoneDropProfile
@export var elite_energy_stone_drop_profile: SpaceEnergyStoneDropProfile

var _current_wave:int=0
var _spawning:bool=false
var _alive_enemies:int=0
var _segment_index:int=SEGMENT_WARMUP
var _cycle:int=0
var _energy_stone_rng := RandomNumberGenerator.new()
var _stage_director: SpaceStageEncounterDirector
var _stage_active: bool = false
var _stage_mode: bool = false
var _stage_faulted: bool = false
var _stage_break_pending: bool = false

func _ready()->void:
	_energy_stone_rng.randomize()
	await get_tree().process_frame
	# Game restores transient run state in its _ready before this deferred start.
	# The current wave is restarted from its beginning because enemy/scheduler
	# instances are not part of the present runtime checkpoint.
	var game := get_parent()
	if game != null and game.has_method("get_stage_director_for_spawner"):
		_stage_director = game.call("get_stage_director_for_spawner") as SpaceStageEncounterDirector
	if _stage_director != null:
		_start_finite_stage()
		return
	var saved_wave := int(GameState.wave)
	if saved_wave > 0:
		_start_wave(initial_wave_for_checkpoint(saved_wave), false)
	else:
		_start_next_wave()

## A resumed run restarts its saved wave; a new run starts at wave one.
## Kept pure so the resume policy can be regression-tested without spawning actors.
static func initial_wave_for_checkpoint(saved_wave: int) -> int:
	return saved_wave if saved_wave > 0 else 1

## Persist the drop RNG stream with the battle state so a restored encounter
## does not reroll a different sequence from the same point in combat.
func capture_energy_stone_drop_rng_state() -> int:
	return int(_energy_stone_rng.state)

func restore_energy_stone_drop_rng_state(state: int) -> bool:
	if not is_inside_tree():
		return false
	_energy_stone_rng.state = state
	return true

## 第 1 波热身、第 2 波压力、第 3 波精英、第 4 波喘息，第 5 波回到热身。
func segment_for_wave(wave:int)->int:
	return (wave - 1) % SEGMENT_LABELS.size()

func cycle_for_wave(wave:int)->int:
	return int(float(wave - 1) / float(SEGMENT_LABELS.size()))

func current_segment_label()->String:
	return SEGMENT_LABELS[_segment_index]

func current_segment()->int:
	return _segment_index

## Finite stages are injected by Game before this scene enters the SceneTree.
## With no director, the legacy endless loop below remains unchanged.
func _start_finite_stage() -> void:
	if _stage_director == null:
		_fault_stage("finite stage director is missing")
		return
	var resuming_interbeat := _stage_director.state() == SpaceStageEncounterDirector.State.ACTIVE
	var beat: Dictionary
	if _stage_director.state() == SpaceStageEncounterDirector.State.READY:
		beat = _stage_director.begin()
	elif resuming_interbeat:
		beat = _stage_director.current_beat()
	else:
		_fault_stage("finite stage director is not resumable")
		return
	if beat.is_empty():
		_fault_stage("finite stage director could not provide a beat")
		return
	_stage_active = true
	_stage_mode = true
	if resuming_interbeat:
		# A checkpoint is only captured in the inter-beat window. Reapply the
		# authored break on resume rather than silently skipping pacing.
		_stage_break_pending = true
		await get_tree().create_timer(maxf(0.0, float(beat.get("break_seconds", 0.0))), false).timeout
		if not is_inside_tree() or _stage_faulted:
			return
		_stage_break_pending = false
	_start_stage_beat(beat)

func _start_stage_beat(beat: Dictionary) -> void:
	if not _stage_active or _stage_faulted:
		return
	var profile: Variant = beat.get("difficultyProfile", {})
	if not (profile is Dictionary) or not bool(profile.get("valid", false)):
		_fault_stage("stage difficulty profile is invalid")
		return
	var scale := float(profile.get("encounterScale", 1.0))
	if not is_finite(scale) or scale <= 0.0:
		_fault_stage("stage encounter scale is invalid")
		return
	var segment_name := String(beat.get("segment", ""))
	var authored_elites := int(beat.get("elite_count", -1))
	var chasers := _scaled_stage_count(int(beat.get("chaser_count", -1)), scale)
	var shooters := _scaled_stage_count(int(beat.get("shooter_count", -1)), scale)
	# A boss is one unique actor; encounter pressure must not duplicate the boss count.
	var elites := 1 if segment_name == "boss" and authored_elites == 1 else _scaled_stage_count(authored_elites, scale)
	if chasers < 0 or shooters < 0 or elites < 0:
		_fault_stage("authored stage composition is malformed")
		return
	if segment_name != "boss" and (chasers > 0 or elites > 0) and chaser_scene == null:
		_fault_stage("stage requires a chaser scene but none is configured")
		return
	if shooters > 0 and shooter_scene == null:
		_fault_stage("stage requires a shooter scene but none is configured")
		return
	_current_wave = int(beat.get("beatIndex", 0)) + 1
	_segment_index = SEGMENT_WARMUP
	_cycle = 0
	GameState.set_wave(_current_wave)
	var segment_labels := {"warmup": "热身", "pressure": "压力", "elite": "精英", "rest": "喘息", "boss": "精英"}
	GameState.set_segment(String(segment_labels.get(segment_name, "热身")))
	_spawning = true
	if segment_name == "boss":
		var boss_id := String(beat.get("boss_id", "")).strip_edges()
		var game := get_parent()
		if boss_id.is_empty() or chasers != 0 or shooters != 0 or elites != 1:
			_fault_stage("boss beat must identify exactly one boss and no generic enemies")
			return
		if game == null or not game.has_method("get_stage_boss_definition_id") or String(game.call("get_stage_boss_definition_id")) != boss_id:
			_fault_stage("boss beat identity does not match the configured stage objective")
			return
		if boss_scene == null:
			_fault_stage("boss beat requires an authored boss actor scene")
			return
		if not _spawn_stage_boss(boss_id, scale):
			_fault_stage("failed to spawn the exact authored stage boss")
			return
	else:
		for index in chasers:
			if not _spawn_stage_enemy(false, false):
				_fault_stage("failed to spawn an authored chaser")
				return
			await get_tree().create_timer(spawn_stagger_seconds, false).timeout
			if not is_inside_tree() or _stage_faulted:
				return
		for index in shooters:
			if not _spawn_stage_enemy(true, false):
				_fault_stage("failed to spawn an authored shooter")
				return
			await get_tree().create_timer(spawn_stagger_seconds, false).timeout
			if not is_inside_tree() or _stage_faulted:
				return
		for index in elites:
			if not _spawn_stage_enemy(false, true):
				_fault_stage("failed to spawn an authored elite")
				return
			await get_tree().create_timer(spawn_stagger_seconds, false).timeout
			if not is_inside_tree() or _stage_faulted:
				return
	_spawning = false
	_check_wave_clear()

func _scaled_stage_count(authored_count: int, scale: float) -> int:
	if authored_count < 0:
		return -1
	if authored_count == 0:
		return 0
	return maxi(1, int(ceil(float(authored_count) * scale)))

func _spawn_stage_boss(boss_id: String, encounter_scale: float) -> bool:
	var boss := boss_scene.instantiate() as Node2D
	if boss == null or not boss.has_method("configure_stage_boss") or not boss.has_signal("died"):
		if boss != null:
			boss.free()
		return false
	if not bool(boss.call("configure_stage_boss", boss_id, encounter_scale)):
		boss.free()
		return false
	var arena := get_parent().get_node_or_null("Arena")
	if arena == null:
		boss.free()
		return false
	boss.tree_exited.connect(_on_enemy_freed)
	boss.died.connect(_on_enemy_died_with_source.bind(boss))
	boss.died.connect(_on_stage_boss_died.bind(boss_id, boss))
	boss.position = _random_edge_position()
	arena.add_child(boss)
	_alive_enemies += 1
	return true

func _on_stage_boss_died(_at: Vector2, boss_id: String, _boss: Node2D) -> void:
	var game := get_parent()
	if game == null or not game.has_method("record_stage_boss_defeated") or not bool(game.call("record_stage_boss_defeated", boss_id)):
		_fault_stage("stage objective rejected the defeated boss identity")

func _spawn_stage_enemy(use_shooter: bool, elite: bool) -> bool:
	var scene := shooter_scene if use_shooter else chaser_scene
	if scene == null:
		return false
	var enemy := scene.instantiate() as Node2D
	if enemy == null:
		return false
	if energy_stone_drop_profile != null and enemy.get("energy_stone_drop_profile") == null:
		enemy.set("energy_stone_drop_profile", energy_stone_drop_profile)
	if elite:
		enemy.set("max_hp", ELITE_BASE_HP)
		enemy.set("speed", ELITE_SPEED)
		enemy.set("score_value", ELITE_SCORE)
		if elite_energy_stone_drop_profile != null:
			enemy.set("energy_stone_drop_profile", elite_energy_stone_drop_profile)
		enemy.scale = Vector2(ELITE_SCALE, ELITE_SCALE)
	enemy.position = _random_edge_position()
	if not enemy.has_signal("died"):
		enemy.free()
		return false
	enemy.tree_exited.connect(_on_enemy_freed)
	enemy.died.connect(_on_enemy_died_with_source.bind(enemy))
	var arena := get_parent().get_node_or_null("Arena")
	if arena == null:
		enemy.free()
		return false
	arena.add_child(enemy)
	_alive_enemies += 1
	return true

func _complete_stage_beat() -> void:
	if not _stage_active or _stage_faulted or _stage_break_pending:
		return
	_stage_break_pending = true
	var completed_beat := _stage_director.current_beat()
	var result := _stage_director.complete_current_beat()
	if not bool(result.get("success", false)):
		_fault_stage("stage director rejected beat completion")
		return
	var break_seconds := maxf(0.0, float(completed_beat.get("break_seconds", wave_break_seconds)))
	await get_tree().create_timer(break_seconds, false).timeout
	if not is_inside_tree() or _stage_faulted:
		return
	if bool(result.get("complete", false)):
		_stage_active = false
		_stage_break_pending = false
		encounters_completed.emit({
			"stageIdentity": _stage_director.stage_identity(),
			"completedBeatCount": _current_wave,
			"status": "encounters_complete"
		})
		return
	_stage_break_pending = false
	var next_beat: Variant = result.get("nextBeat", {})
	if not (next_beat is Dictionary) or next_beat.is_empty():
		_fault_stage("stage director returned an invalid next beat")
		return
	_start_stage_beat(next_beat)

## Finite-stage checkpoints are safe only in the enemy-free inter-beat window.
func can_capture_finite_stage_checkpoint() -> bool:
	return _stage_mode and _stage_active and _stage_director != null and _stage_director.state() == SpaceStageEncounterDirector.State.ACTIVE and _stage_break_pending and not _spawning and _alive_enemies == 0 and not _stage_faulted
func _fault_stage(reason: String) -> void:
	if _stage_faulted:
		return
	_stage_faulted = true
	_stage_active = false
	_spawning = false
	push_error("[Spawner] Finite stage fault: " + reason)
	stage_faulted.emit(reason)

func _start_next_wave()->void:
	_start_wave(_current_wave + 1, true)

func _start_wave(wave_number: int, publish_progression: bool) -> void:
	if wave_number <= 0:
		push_error("[Spawner] Refusing to start an invalid wave number")
		return
	_current_wave = wave_number
	_segment_index = segment_for_wave(_current_wave)
	_cycle = cycle_for_wave(_current_wave)
	if publish_progression:
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
		await get_tree().create_timer(spawn_stagger_seconds, false).timeout
	_spawning=false
	_check_wave_clear()

func _spawn_one(shooter_chance:float, elite:bool)->void:
	var use_shooter :=(not elite) and shooter_scene != null and randf()<shooter_chance
	var scene:=shooter_scene if use_shooter else chaser_scene
	if scene == null:
		return
	var e:Node2D=scene.instantiate()
	if energy_stone_drop_profile != null and e.get("energy_stone_drop_profile") == null:
		e.set("energy_stone_drop_profile", energy_stone_drop_profile)
	if elite:
		e.set("max_hp", ELITE_BASE_HP + ELITE_HP_PER_CYCLE * _cycle)
		e.set("speed", ELITE_SPEED)
		e.set("score_value", ELITE_SCORE)
		if elite_energy_stone_drop_profile != null:
			e.set("energy_stone_drop_profile", elite_energy_stone_drop_profile)
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
	if _stage_mode:
		if _stage_active:
			_complete_stage_beat()
		return
	await get_tree().create_timer(_break_seconds(), false).timeout
	if not is_inside_tree():
		return
	_start_next_wave()

## 喘息段多留两秒：玩家用这段时间决定去哪、要不要去工业舱。
func _break_seconds()->float:
	return REST_BREAK_SECONDS if _segment_index == SEGMENT_REST else wave_break_seconds
