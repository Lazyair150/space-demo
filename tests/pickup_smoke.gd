extends SceneTree
# 拾取物闭环测试：胶囊 → 玩家 → Buff → HUD 文本 → 到期恢复。
# 也覆盖敌人死亡掉落入口、以及"攻击强化接子弹"这个独立验收项。
#
# 说明：用 --script 跑时 autoload 不一定进来，所以这里按需自建 /root/GameState。

const HASTE := "res://data/effects/haste.tres"
const BOOST := "res://data/effects/attack_boost.tres"
const POISON := "res://data/effects/poison.tres"
const PICKUP_SCENE := "res://scenes/pickups/BuffPickup.tscn"
const PLAYER_SCENE := "res://scenes/actors/Player.tscn"
const HUD_SCENE := "res://scenes/ui/HUD.tscn"

var _checks := 0
var _fails := 0
var _root: Node2D
var _player: CharacterBody2D
var _effects: StatusEffectManager
var _hud: CanvasLayer
var _wallet: Node

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
	_wallet = get_root().get_node("GameState")
	var wallet = _wallet
	wallet.persist_wallet = false
	wallet.ore = 0
	wallet.materials = 0
	wallet.attack_level = 0

func _make_pickup(definition: Resource) -> Area2D:
	var pickup: Area2D = load(PICKUP_SCENE).instantiate()
	pickup.set("buff_definition", definition)
	# 放远一点：否则入树瞬间就与玩家重叠、自动被吃掉，后面显式调用会打到已释放节点
	pickup.position = Vector2(600, 400)
	_root.add_child(pickup)
	return pickup

func _run() -> void:
	_ensure_game_state()

	_root = Node2D.new()
	_root.name = "PickupFixture"
	get_root().add_child(_root)

	_player = load(PLAYER_SCENE).instantiate()
	_root.add_child(_player)
	await process_frame
	_player.set_physics_process(false)
	_effects = _player.get_node("Effects")
	_check(_effects != null, "玩家身上有状态效果管理器")
	if _effects == null:
		_finish()
		return

	var stats: StatCalculator = _player.get_node("Stats")
	var base_fire: float = _player.fire_rate
	_check(is_equal_approx(base_fire, 0.18), "开局射速是基础值", str(base_fire))

	# 1) 急速胶囊：碰到玩家 → 生效 → 胶囊自己消失
	var haste: BuffDefinition = load(HASTE)
	var pickup := _make_pickup(haste)
	await process_frame
	pickup._on_body_entered(_player)
	_check(_effects.has(&"haste"), "撞到急速胶囊后效果生效")
	_check(is_equal_approx(_player._stat_value(&"fire_rate", base_fire), base_fire * 0.6), "折算后的射速是六折",
		str(_player._stat_value(&"fire_rate", base_fire)))
	_check(pickup.is_queued_for_deletion(), "胶囊被吃掉后自己移除")
	_check(_effects.count() == 1 and stats.modifier_count(&"fire_rate") == 1, "只登记一个实例、一条修正器",
		"effects=%d mods=%d" % [_effects.count(), stats.modifier_count(&"fire_rate")])

	# 2) 再捡一个：刷新剩余时间，不叠层
	var before: float = _effects.remaining(&"haste")
	_effects.advance(2.0)
	var pickup2 := _make_pickup(haste)
	await process_frame
	pickup2._on_body_entered(_player)
	_check(_effects.stacks(&"haste") == 1, "重复拾取不叠层", str(_effects.stacks(&"haste")))
	_check(_effects.remaining(&"haste") > before - 1.0, "重复拾取把剩余时间刷回去",
		"%.2f → %.2f" % [before, _effects.remaining(&"haste")])
	_check(stats.modifier_count(&"fire_rate") == 1, "刷新没有叠加第二条修正器",
		str(stats.modifier_count(&"fire_rate")))

	# 3) 到期：射速精确回到基础值
	_effects.advance(6.0)
	_check(not _effects.has(&"haste"), "到期后效果移除")
	_check(is_equal_approx(_player._stat_value(&"fire_rate", base_fire), base_fire), "到期后射速精确恢复",
		str(_player._stat_value(&"fire_rate", base_fire)))
	_check(stats.modifier_count(&"fire_rate") == 0, "到期后修正器清干净",
		str(stats.modifier_count(&"fire_rate")))

	# 4) 攻击强化：最终值 → 子弹伤害（独立验收项）
	var boost: BuffDefinition = load(BOOST)
	var pickup3 := _make_pickup(boost)
	await process_frame
	pickup3._on_body_entered(_player)
	_check(is_equal_approx(_player.attack_final(), 1.5), "攻击强化把最终攻击力算成 1.5", str(_player.attack_final()))
	_check(_player.attack_damage_int() == 2, "取整后是 2 点伤害", str(_player.attack_damage_int()))

	_player._shoot_cooldown = 0.0
	_player._shoot()
	await process_frame
	var bullet: Area2D = null
	for child in _player.get_parent().get_children():
		if child.is_in_group("player_bullet"):
			bullet = child
			break
	_check(bullet != null, "开火生成了子弹")
	if bullet != null:
		_check(int(bullet.get("damage")) == 2, "子弹真的带 2 点伤害（不只是算得出来）", str(bullet.get("damage")))
		bullet.queue_free()
	_effects.advance(11.0)
	_check(_player.attack_damage_int() == 1, "攻击强化到期后伤害回到 1", str(_player.attack_damage_int()))

	# 5) 中毒：走玩家受伤入口，无敌期间不吃第二次
	var poison: BuffDefinition = load(POISON)
	_player._invuln = 0.0
	var hp_before: int = _player.hp
	_effects.apply(poison, _player)
	_effects.advance(1.05)
	_check(_player.hp == hp_before - 1, "中毒每秒掉 1 点", "%d → %d" % [hp_before, _player.hp])
	var hp_mid: int = _player.hp
	_effects.advance(0.55)
	_check(_player.hp == hp_mid, "无敌窗口内不连续掉血", str(_player.hp))
	# 物理帧被关掉了，无敌计时不会自己走，这里手动清零再验下一次 tick
	_player._invuln = 0.0
	_effects.advance(1.0)
	_check(_player.hp == hp_mid - 1, "无敌结束后下一次 tick 照常掉血", str(_player.hp))
	_effects.advance(3.0)
	_check(not _effects.has(&"poison"), "中毒到期移除")
	var hp_after: int = _player.hp
	_player._invuln = 0.0
	_effects.advance(3.0)
	_check(_player.hp == hp_after, "中毒到期后不再掉血", str(_player.hp))

	# 6) 没有 Buff 系统的玩家：胶囊不该被吞掉
	var stranger := Area2D.new()
	stranger.name = "Stranger"
	stranger.add_to_group("player")
	_root.add_child(stranger)
	var pickup4 := _make_pickup(haste)
	await process_frame
	pickup4._on_body_entered(stranger)
	_check(not pickup4.is_queued_for_deletion(), "没有 Buff 系统的玩家不会吞掉胶囊")
	pickup4.queue_free()
	stranger.queue_free()

	# 7) HUD：显示名字和剩余秒数
	_hud = load(HUD_SCENE).instantiate()
	get_root().add_child(_hud)
	await process_frame
	_effects.apply(load(HASTE), _player)
	_hud._bind_player_effects()
	_hud._refresh_buff_text()
	var text: String = _hud._buff_label.text
	_check(text.contains("急速"), "HUD 显示效果名字", text)
	_check(text.contains("s"), "HUD 显示剩余秒数", text)
	_effects.clear_all()
	_hud._refresh_buff_text()
	_check(_hud._buff_label.text.is_empty(), "效果结束后 HUD 清空", _hud._buff_label.text)

	# 8) 敌人死亡 → 掉落入口
	var chaser: CharacterBody2D = load("res://scenes/actors/EnemyChaser.tscn").instantiate()
	chaser.position = Vector2(900, 500)
	_root.add_child(chaser)
	# 关掉物理：否则它出生就撞在玩家身上自己死掉，测不到"受伤致死"这条出口
	chaser.set_physics_process(false)
	await process_frame
	var chaser_hp: int = chaser.max_hp
	var died_at: Array = []
	chaser.died.connect(func(at): died_at.append(at))
	chaser.take_damage(chaser_hp)
	await process_frame
	_check(not died_at.is_empty(), "敌人死亡会发出 died(位置) 信号")
	if not died_at.is_empty():
		# chaser 此时已 queue_free，位置要先记下来再比
		_check((died_at[0] as Vector2).distance_to(Vector2(900, 500)) < 4.0, "信号带的是死亡位置",
			str(died_at[0]))

	# 9) Spawner 掉落：概率拉满时必须掉一个胶囊
	var arena := Node2D.new()
	arena.name = "Arena"
	_root.add_child(arena)
	var spawner := Node.new()
	spawner.set_script(load("res://scripts/Spawner.gd"))
	spawner.set("pickup_scene", load(PICKUP_SCENE))
	spawner.set("pickup_chance", 1.0)
	# 导出的类型是 Array[BuffDefinition]，用无类型数组赋值会被拒（静默留空）
	var effects_list: Array[BuffDefinition] = [load(HASTE)]
	spawner.set("pickup_effects", effects_list)
	_root.add_child(spawner)
	await process_frame
	spawner._on_enemy_died(Vector2(300, 200))
	await process_frame
	var dropped := 0
	var dropped_node: Area2D = null
	for child in arena.get_children():
		if child.get_script() != null and child.get_script().resource_path.ends_with("BuffPickup.gd"):
			dropped += 1
			dropped_node = child
	_check(dropped == 1, "敌人死后在 Arena 里掉了一个胶囊", str(dropped))
	if dropped_node != null:
		_check(dropped_node.global_position.distance_to(Vector2(300, 200)) < 4.0, "胶囊掉在死亡位置",
			str(dropped_node.global_position))
		var tint: Color = dropped_node.get("tint")
		_check(tint.b > tint.r, "急速胶囊被染成偏冷色", str(tint))

	_finish()

func _finish() -> void:
	for node in [_hud, _root]:
		if node != null and is_instance_valid(node):
			node.free()
	var wallet = get_root().get_node_or_null("GameState")
	if wallet != null:
		wallet.ore = 0
		wallet.materials = 0
		wallet.attack_level = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	print("=== %d 项检查，%d 项失败 ===" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
