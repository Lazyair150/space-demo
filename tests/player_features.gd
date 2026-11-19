extends SceneTree
# 玩家能力组件自测：场景挂载 / 按键切换 / 护盾抵挡与无敌窗口 / 双发不丢 / 子弹落点
# 用法：godot.exe --headless --path . --script res://tests/player_features.gd

var _checks := 0
var _fails := 0

func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("PASS ", label, ("（%s）" % detail) if detail != "" else "")
	else:
		_fails += 1
		print("FAIL ", label, ("（%s）" % detail) if detail != "" else "")

func _game_state() -> Node:
	var node = get_root().get_node_or_null("GameState")
	if node == null:
		node = load("res://globals/GameState.gd").new()
		node.name = "GameState"
		get_root().add_child(node)
	if "persist_wallet" in node:
		node.persist_wallet = false
	return node

func _press(features: Node, action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	features._unhandled_input(ev)

func _bullets(parent: Node) -> Array:
	var out: Array = []
	for child in parent.get_children():
		if child.is_in_group("player_bullet") or child.get_script() != null and String(child.get_script().resource_path).ends_with("PlayerBullet.gd"):
			out.append(child)
	return out

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var gs := _game_state()
	gs.ore = 0
	gs.materials = 0
	gs.attack_level = 0

	# 用一个不在原点的父节点：能抓出"先设 global_position 再加入树"的落点错误
	var arena := Node2D.new()
	arena.position = Vector2(300, 120)
	get_root().add_child(arena)

	var player = load("res://scenes/actors/Player.tscn").instantiate()
	arena.add_child(player)
	await process_frame

	var features = player.get_node_or_null("PlayerFeatures")
	_ok("玩家场景带能力管理器", features != null)
	_ok("能力管理器挂了能量盾", features.get_node_or_null("EnergyShield") != null)
	_ok("能力管理器挂了双发", features.get_node_or_null("DoubleShot") != null)

	var shield = features.get_node("EnergyShield")
	var double_shot = features.get_node("DoubleShot")
	_ok("能量盾的可见节点是 Visual", shield.get_node_or_null("Visual") != null)
	_ok("能量盾初始关闭", shield.active == false and shield.get_node("Visual").visible == false)

	# 按键切换（走 _unhandled_input，验输入映射确实通到能力）
	_press(features, &"shield")
	_ok("按盾键开启能量盾", shield.active == true and shield.get_node("Visual").visible == true)
	_press(features, &"shield")
	_ok("再按一次关闭能量盾", shield.active == false)

	# 护盾抵挡 + 无敌窗口
	_press(features, &"shield")
	var hp_before: int = player.hp
	player.take_damage(1)
	_ok("护盾替玩家挡下这次伤害", player.hp == hp_before, "hp %d" % player.hp)
	_ok("抵挡后护盾自动关闭", shield.active == false)
	_ok("抵挡后玩家进入无敌", player.is_invulnerable() == true)
	player.take_damage(1)
	_ok("无敌窗口内再挨一下不掉血", player.hp == hp_before, "hp %d" % player.hp)
	player.grant_invuln(0.0)
	player._invuln = 0.0
	player.take_damage(1)
	_ok("无敌结束后照常掉血", player.hp == hp_before - 1, "hp %d" % player.hp)

	# 子弹落点：父节点在 (300,120)，子弹应落在炮口世界坐标
	var before_count := _bullets(arena).size()
	player.spawn_bullet()
	# 不等待：子弹一入树就开始飞，等一帧再比坐标等于在跟飞行轨迹比
	var bullets := _bullets(arena)
	_ok("发射后场上多一颗子弹", bullets.size() == before_count + 1, "%d → %d" % [before_count, bullets.size()])
	if bullets.size() > 0:
		var b = bullets[bullets.size() - 1]
		var muzzle := player.get_node("Muzzle") as Node2D
		_ok("子弹落在炮口世界坐标", b.global_position.distance_to(muzzle.global_position) < 1.0,
			"子弹 %s / 炮口 %s" % [str(b.global_position), str(muzzle.global_position)])

	# 双发：一次攻击 → 0.15s 后补一发
	_press(features, &"double_shot")
	_ok("按双发键开启", double_shot.active == true)
	var n0 := _bullets(arena).size()
	player._shoot()
	await create_timer(0.35).timeout
	var n1 := _bullets(arena).size()
	_ok("一次攻击打出两发", n1 == n0 + 2, "%d → %d" % [n0, n1])

	# 高射速场景：两次攻击间隔 < second_shot_interval，第二发不能被吃掉
	var n2 := _bullets(arena).size()
	player._shoot()
	player._shoot()
	await create_timer(0.5).timeout
	var n3 := _bullets(arena).size()
	_ok("射速快于间隔时两发都在", n3 == n2 + 4, "%d → %d" % [n2, n3])

	# 第三种能力（穿透弹）：不改 Player.gd / PlayerFeatures.gd，只加一个能力组件
	var pierce = features.get_node_or_null("PiercingShot")
	_ok("能力管理器挂了穿透弹", pierce != null)
	if pierce != null:
		_press(features, &"pierce")
		_ok("按穿透键开启", pierce.active == true)
		var n4 := _bullets(arena).size()
		player.spawn_bullet()
		var fresh := _bullets(arena)
		_ok("开启后发射的子弹多一颗", fresh.size() == n4 + 1)
		var pb = fresh[fresh.size() - 1]
		_ok("新子弹带上了穿透标记", int(pb.get("pierce_count")) == 1, "pierce=%s" % str(pb.get("pierce_count")))

		# 手动喂两个"敌人"，验证一发穿两个
		var dummies: Array = []
		for i in 2:
			var d := Node2D.new()
			d.set_script(load("res://tests/helpers/damage_dummy.gd"))
			arena.add_child(d)
			dummies.append(d)
		pb._consume_hit(dummies[0])
		_ok("命中第一个目标后子弹还在飞", is_instance_valid(pb) and not pb.is_queued_for_deletion())
		pb._consume_hit(dummies[1])
		_ok("命中第二个目标后子弹消失", pb.is_queued_for_deletion())
		_ok("两个目标都吃到伤害", int(dummies[0].hits) == 1 and int(dummies[1].hits) == 1,
			"%d / %d" % [int(dummies[0].hits), int(dummies[1].hits)])
		_press(features, &"pierce")

	# 清场，避免子节点泄漏
	for b in _bullets(arena):
		b.free()
	for child in arena.get_children():
		if child.get_script() != null and String(child.get_script().resource_path).ends_with("damage_dummy.gd"):
			child.free()
	player.free()
	arena.free()
	await process_frame
	print("=== %d 项检查，%d 项失败 ===" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
