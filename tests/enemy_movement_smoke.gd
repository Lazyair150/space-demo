extends SceneTree
# 敌机移动与子弹生命周期回归：
#   1. 射手在理想距离区间内必须真正减速（Vector2.move_toward 的返回值要写回）；
#   2. 射手子弹先入树再设全局坐标，父节点有非零变换也不偏；
#   3. 玩家子弹撞到"已释放"的对象时不能抛错。

const SHOOTER_SCENE := "res://scenes/actors/EnemyShooter.tscn"
const PLAYER_SCENE := "res://scenes/actors/Player.tscn"

var _checks := 0
var _fails := 0
var _root: Node2D

func _init() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("PASS %s%s" % [what, "" if detail.is_empty() else "（实际：%s）" % detail])
	else:
		_fails += 1
		print("FAIL %s%s" % [what, "" if detail.is_empty() else "（实际：%s）" % detail])

func _ensure_game_state() -> void:
	if get_root().get_node_or_null("GameState") == null:
		var gs = load("res://globals/GameState.gd").new()
		gs.name = "GameState"
		get_root().add_child(gs)
	get_root().get_node("GameState").persist_wallet = false

func _run() -> void:
	_ensure_game_state()
	_root = Node2D.new()
	_root.name = "MovementFixture"
	get_root().add_child(_root)

	var player: CharacterBody2D = load(PLAYER_SCENE).instantiate()
	player.position = Vector2(640, 360)
	_root.add_child(player)
	await process_frame
	player.set_physics_process(false)

	# ======== 1. 理想距离区间内必须减速到 0 ========
	var shooter: CharacterBody2D = load(SHOOTER_SCENE).instantiate()
	var preferred: float = shooter.preferred_distance
	var tolerance: float = shooter.distance_tolerance
	shooter.position = player.position + Vector2(preferred, 0)
	shooter.set("fire_interval", 999.0)
	_root.add_child(shooter)
	await process_frame
	shooter.set_physics_process(false)

	# 先给一个非零初速度，模拟"刚刚还在飞过来"。
	# 每帧把位置摆回理想距离，避免它滑出区间又被加速，单独观察"减速"这一件事。
	shooter.velocity = Vector2(-120, 0)
	for i in range(45):
		shooter.position = player.position + Vector2(preferred, 0)
		shooter._physics_process(1.0 / 60.0)
	_check(shooter.velocity.length() < 1.0, "进入理想区间后速度收敛到接近 0",
		"速度=%.2f" % shooter.velocity.length())

	# ======== 2. 区间外仍然全速移动 ========
	shooter.position = player.position + Vector2(preferred + tolerance + 200.0, 0)
	shooter.velocity = Vector2.ZERO
	shooter._physics_process(1.0 / 60.0)
	_check(absf(shooter.velocity.length() - shooter.speed) < 1.0,
		"距离过远时按全速接近", "速度=%.2f" % shooter.velocity.length())
	shooter.position = player.position + Vector2(10, 0)
	shooter.velocity = Vector2.ZERO
	shooter._physics_process(1.0 / 60.0)
	_check(absf(shooter.velocity.length() - shooter.speed) < 1.0,
		"距离过近时按全速后撤", "速度=%.2f" % shooter.velocity.length())

	# ======== 3. 子弹出生点：父节点带非零变换也不偏 ========
	var arena := Node2D.new()
	arena.name = "OffsetArena"
	arena.position = Vector2(100, 50)
	_root.add_child(arena)
	await process_frame
	var shooter2: CharacterBody2D = load(SHOOTER_SCENE).instantiate()
	shooter2.position = Vector2(300, 300)
	arena.add_child(shooter2)
	await process_frame
	shooter2.set_physics_process(false)
	shooter2._fire(Vector2.RIGHT)
	# 立刻读位置：子弹下一帧就会飞出去 6 像素左右
	var spawned: Array = []
	for child in arena.get_children():
		if child is Area2D and String(child.get_script().resource_path).ends_with("EnemyBullet.gd"):
			spawned.append(child)
	_check(spawned.size() == 1, "射手发射了一发子弹", str(spawned.size()))
	if spawned.size() == 1:
		var expected := shooter2.global_position + Vector2.RIGHT * 32.0
		_check(spawned[0].global_position.distance_to(expected) < 0.01,
			"子弹落在炮口的世界坐标上",
			"%s vs %s" % [spawned[0].global_position, expected])

	# ======== 4. 玩家子弹撞到已释放对象不崩 ========
	var victim := Node2D.new()
	victim.name = "SoonFreed"
	_root.add_child(victim)
	await process_frame
	var bullet: Area2D = load("res://scenes/actors/PlayerBullet.tscn").instantiate()
	_root.add_child(bullet)
	await process_frame
	victim.free()
	bullet._consume_hit(victim)
	_check(is_instance_valid(bullet), "撞到已释放对象时子弹仍在", "存活=%s" % str(is_instance_valid(bullet)))
	_check(bullet.damage == 1, "子弹伤害未被改动", str(bullet.damage))

	_finish()

func _finish() -> void:
	if is_instance_valid(_root):
		_root.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	print("=== %d 项检查，%d 项失败 ===" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
