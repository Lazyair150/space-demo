extends SceneTree
# 临时状态效果（Buff）第一阶段自测：生命周期 / 撤回 / 定时 / 修正器汇总 / 不污染存档
# 用法：godot.exe --headless --path . --script res://tests/effects_smoke.gd

var _checks := 0
var _fails := 0

func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("PASS ", label, ("（%s）" % detail) if detail != "" else "")
	else:
		_fails += 1
		print("FAIL ", label, ("（%s）" % detail) if detail != "" else "")

func _near(a: float, b: float, eps: float = 0.0001) -> bool:
	return absf(a - b) <= eps

func _game_state() -> Node:
	var node = get_root().get_node_or_null("GameState")
	if node == null:
		node = load("res://globals/GameState.gd").new()
		node.name = "GameState"
		get_root().add_child(node)
	if "persist_wallet" in node:
		node.persist_wallet = false
	node.ore = 0
	node.materials = 0
	node.attack_level = 0
	return node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var gs := _game_state()

	var arena := Node2D.new()
	get_root().add_child(arena)
	var player = load("res://scenes/actors/Player.tscn").instantiate()
	arena.add_child(player)
	await process_frame

	# 管理器自己在跑 _process，测试用显式 delta 推进
	var effects = player.get_node("Effects")
	var stats = player.get_node("Stats")
	effects.set_process(false)

	var haste: BuffDefinition = load("res://data/effects/haste.tres")
	var boost: BuffDefinition = load("res://data/effects/attack_boost.tres")
	var poison: BuffDefinition = load("res://data/effects/poison.tres")
	_ok("三个 Buff 定义能加载", haste != null and boost != null and poison != null)

	var base_fire: float = player.fire_rate
	var base_attack: int = player.attack_base()
	_ok("基础攻击力来自 GameState（1）", base_attack == 1, "attack_base=%d" % base_attack)

	# --- 1. 急速：修正 fire_rate，到期精确还原 ---
	var inst = player.grant_buff(haste)
	_ok("急速施加成功", inst != null and effects.has(&"haste"))
	_ok("fire_rate 被乘到 0.6", _near(player._stat_value(&"fire_rate", base_fire), base_fire * 0.6),
		"%.4f" % player._stat_value(&"fire_rate", base_fire))
	_ok("Stats 里登记了一条修正", stats.modifier_count(&"fire_rate") == 1)
	effects.advance(4.9)
	_ok("未到期时仍然生效", effects.has(&"haste") and _near(player._stat_value(&"fire_rate", base_fire), base_fire * 0.6))
	effects.advance(0.2)
	_ok("到期后被移除", not effects.has(&"haste"))
	_ok("fire_rate 精确还原", _near(player._stat_value(&"fire_rate", base_fire), base_fire),
		"%.6f" % player._stat_value(&"fire_rate", base_fire))
	_ok("修正器撤干净", stats.modifier_count(&"fire_rate") == 0)

	# --- 2. 两个不同 Buff 同时存在，互不干扰 ---
	player.grant_buff(haste)
	var inst2 = player.grant_buff(boost)
	_ok("两个 Buff 并存", effects.count() == 2 and effects.has(&"haste") and effects.has(&"attack_boost"))
	_ok("攻击力被临时提到 1.5 倍", _near(player.attack_final(), 1.5), "%.4f" % player.attack_final())
	_ok("永久成长没被改写", gs.attack_level == 0 and player.attack_base() == 1)
	effects.advance(5.1)
	_ok("急速先到期，攻击强化还在", not effects.has(&"haste") and effects.has(&"attack_boost"))
	_ok("攻击力仍是被强化的值", _near(player.attack_final(), 1.5))
	effects.advance(5.0)
	_ok("攻击强化到期后攻击力回到 1", _near(player.attack_final(), 1.0), "%.4f" % player.attack_final())
	_ok("GameState 依旧未被改动", gs.attack_level == 0)

	# --- 3. 重复施加按配置策略：刷新时间、不叠层、不残留 ---
	var first = player.grant_buff(haste)
	effects.advance(3.0)
	var remaining_before: float = effects.remaining(&"haste")
	player.grant_buff(haste)
	_ok("重复施加刷新剩余时间", effects.remaining(&"haste") > remaining_before, "%.2f → %.2f" % [remaining_before, effects.remaining(&"haste")])
	_ok("重复施加不叠层", effects.stacks(&"haste") == 1 and effects.count() == 1)
	_ok("重复施加不残留旧修正", stats.modifier_count(&"fire_rate") == 1)
	# 连做 5 轮施加/移除，检查没有残留
	for i in 5:
		player.grant_buff(haste)
		effects.remove(&"haste")
	_ok("反复施加/移除后无残留", effects.count() == 0 and stats.modifier_count() == 0,
		"effects=%d mods=%d" % [effects.count(), stats.modifier_count()])

	# --- 4. 中毒：按秒结算，不叠层，到期停止 ---
	player.grant_invuln(0.0)
	player._invuln = 0.0
	var hp_before: int = player.hp
	var p = player.grant_buff(poison)
	_ok("中毒施加成功且用的是专用实例", p is PoisonBuffInstance)
	effects.advance(0.9)
	_ok("不满一秒不结算", player.hp == hp_before, "hp %d" % player.hp)
	effects.advance(0.2)
	_ok("满一秒掉 1 点", player.hp == hp_before - 1, "hp %d" % player.hp)
	# 掉血会带无敌时间，这里手动清掉，验证中毒确实按秒继续跑（而不是被无敌卡住一次就完）
	player._invuln = 0.0
	effects.advance(1.0)
	_ok("再过一秒再掉 1 点", player.hp == hp_before - 2, "hp %d" % player.hp)
	player.grant_buff(poison)
	_ok("重复中毒只刷新不叠层", effects.stacks(&"poison") == 1)

	# --- 5. 中毒不绕过护盾/无敌 ---
	player._invuln = 0.0
	var hp_now: int = player.hp
	effects.clear_all()
	player.grant_invuln(1.0)
	player.grant_buff(poison)
	effects.advance(1.2)
	_ok("无敌期间中毒不掉血", player.hp == hp_now, "hp %d" % player.hp)
	effects.clear_all()
	player._invuln = 0.0
	player.hp = player.max_hp
	player.get_node("PlayerFeatures").set_feature_active(&"shield", true)
	var hp_shield: int = player.hp
	player.grant_buff(poison)
	effects.advance(1.2)
	_ok("护盾挡住中毒那一下", player.hp == hp_shield, "hp %d" % player.hp)
	_ok("护盾被消耗掉（和中弹一致）", player.get_node("PlayerFeatures").get_node("EnergyShield").active == false)

	# --- 6. 到期停止：中毒消失后不再造成伤害 ---
	effects.clear_all()
	player._invuln = 0.0
	player.grant_buff(poison, 1.5)
	effects.advance(1.2)
	var hp_after_tick: int = player.hp
	player._invuln = 0.0
	effects.advance(3.0)
	_ok("中毒到期后不再掉血", player.hp == hp_after_tick, "hp %d" % player.hp)
	_ok("中毒已不在列表", not effects.has(&"poison"))

	# --- 7. 属性计算阶段：加算先于乘算 ---
	var calc: StatCalculator = load("res://scripts/player/stats/StatCalculator.gd").new()
	arena.add_child(calc)
	calc.add_modifier("a", &"attack", StatCalculator.Stage.FLAT, 10.0)
	calc.add_modifier("b", &"attack", StatCalculator.Stage.FLAT, 20.0)
	calc.add_modifier("c", &"attack", StatCalculator.Stage.MULT, 1.5)
	_ok("加算先于乘算：100+10+20 再 ×1.5 = 195", _near(calc.value_of(&"attack", 100.0), 195.0),
		"%.2f" % calc.value_of(&"attack", 100.0))
	calc.set_bounds(&"attack", 0.0, 120.0)
	_ok("钳制阶段生效", _near(calc.value_of(&"attack", 100.0), 120.0))
	_ok("按 owner 撤销后回到基础值", calc.remove_modifiers_by_owner("a") == 1 and _near(calc.value_of(&"attack", 100.0), 120.0))

	# --- 8. 不进入存档：存档 payload 里没有 Buff 字段 ---
	var saved_has_effects := false
	var save_path := ProjectSettings.globalize_path("user://industrial_save.json")
	if FileAccess.file_exists(save_path):
		var text := FileAccess.get_file_as_string(save_path)
		var data = JSON.parse_string(text)
		saved_has_effects = data is Dictionary and (data.has("effects") or data.has("buffs"))
	_ok("存档里没有 Buff/Effect 字段", not saved_has_effects)

	for child in arena.get_children():
		child.free()
	arena.free()
	await process_frame
	print("=== %d 项检查，%d 项失败 ===" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
