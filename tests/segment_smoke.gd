extends SceneTree
## 波次段落自测：热身 → 压力 → 精英 → 喘息 → 热身。
## 依据 docs/design/07-tiny-wizard-对照与改造.md §3.2-A。

var _checks := 0
var _fails := 0
var _spawner: Node
var _arena: Node2D

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("PASS ", what)
	else:
		_fails += 1
		print("FAIL ", what)

func _run() -> void:
	var gs := get_root().get_node_or_null("GameState")
	if gs == null:
		gs = load("res://globals/GameState.gd").new()
		gs.name = "GameState"
		get_root().add_child(gs)
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	gs.ore = 0
	gs.materials = 0
	gs.attack_level = 0

	var parent := Node.new()
	parent.name = "SegmentFixture"
	get_root().add_child(parent)
	_arena = Node2D.new()
	_arena.name = "Arena"
	parent.add_child(_arena)

	_spawner = load("res://scripts/Spawner.gd").new()
	_spawner.name = "Spawner"
	_spawner.shooter_scene = load("res://scenes/actors/EnemyShooter.tscn")
	_spawner.chaser_scene = load("res://scenes/actors/EnemyChaser.tscn")
	# 测试里压缩等待时间，逻辑不变
	_spawner.wave_break_seconds = 0.5
	_spawner.spawn_stagger_seconds = 0.02
	parent.add_child(_spawner)

	# ---- 第 1 波：热身 ----
	_check(await _wait_wave(1), "进入第 1 波")
	await _settle()
	_check(gs.segment == "热身", "第 1 波是热身（实际：%s）" % gs.segment)
	_check(_alive() == 1, "热身波 1 只（实际：%d）" % _alive())
	_kill_all()
	await _settle()

	# ---- 第 2 波：压力 ----
	_check(await _wait_wave(2), "进入第 2 波")
	await _settle()
	_check(gs.segment == "压力", "第 2 波是压力（实际：%s）" % gs.segment)
	_check(_alive() == 2, "压力波 2 只（实际：%d）" % _alive())
	_kill_all()
	await _settle()

	# ---- 第 3 波：精英 ----
	_check(await _wait_wave(3), "进入第 3 波")
	await _settle()
	_check(gs.segment == "精英", "第 3 波是精英（实际：%s）" % gs.segment)
	var elites := _enemies()
	_check(elites.size() == 1, "精英波 1 只（实际：%d）" % elites.size())
	if elites.size() > 0:
		var elite: Node2D = elites[0]
		_check(int(elite.get("max_hp")) >= 3, "精英血量被放大（实际：%s）" % str(elite.get("max_hp")))
		_check(elite.scale.x > 1.2, "精英体型被放大（实际：%.2f）" % elite.scale.x)
		_check(int(elite.get("score_value")) > 10, "精英分数更高（实际：%s）" % str(elite.get("score_value")))
	_kill_all()
	await _settle()

	# ---- 第 4 波：喘息 ----
	_check(await _wait_wave(4), "进入第 4 波")
	await _settle()
	_check(gs.segment == "喘息", "第 4 波是喘息（实际：%s）" % gs.segment)
	_check(_alive() == 0, "喘息波不刷怪（实际：%d）" % _alive())

	# ---- 第 5 波：回到热身 ----
	_check(await _wait_wave(5), "进入第 5 波")
	await _settle()
	_check(gs.segment == "热身", "第 5 波回到热身（实际：%s）" % gs.segment)

	_kill_all()
	await process_frame
	parent.queue_free()
	await process_frame
	gs.ore = 0
	gs.materials = 0
	gs.attack_level = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	print("=== %d 项检查，%d 项失败 ===" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)

func _enemies() -> Array:
	var out: Array = []
	for e in get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			out.append(e)
	return out

func _alive() -> int:
	return _enemies().size()

func _settle() -> void:
	# 等刷怪收尾：stagger 0.02 × 最多 4 只，给 0.3 秒足够
	await create_timer(0.3).timeout

func _kill_all() -> void:
	for e in _enemies():
		e.queue_free()
	await process_frame
	await process_frame

func _wait_wave(target: int) -> bool:
	var gs := get_root().get_node("GameState")
	for i in 1200:
		if int(gs.wave) >= target:
			return true
		await process_frame
	return false
