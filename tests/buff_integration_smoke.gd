extends SceneTree
# 阶段 B 集成验证：瞄准辅助（暴击率 +25%）与生命汲取（吸血 +50%）真正接进玩法。
# 重点不是"各自生效"，而是两个 Buff 同时存在时不互相干扰：
#   · 各自只登记自己的修正器；
#   · 一个刷新不重置另一个的剩余时间；
#   · 一个过期/被移除不带走另一个的修正器；
#   · 死亡时全部撤干净。

const PLAYER_SCENE := "res://scenes/actors/Player.tscn"
const AIM := "res://data/effects/aim_assist.tres"
const LIFESTEAL := "res://data/effects/lifesteal.tres"
const PICKUP_SCENE := "res://scenes/pickups/BuffPickup.tscn"

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

func _new_player(pos: Vector2) -> CharacterBody2D:
	var p: CharacterBody2D = load(PLAYER_SCENE).instantiate()
	p.position = pos
	_root.add_child(p)
	p.set_physics_process(false)
	return p

func _run() -> void:
	_ensure_game_state()
	_root = Node2D.new()
	_root.name = "BuffIntegration"
	get_root().add_child(_root)

	var aim: BuffDefinition = load(AIM)
	var steal: BuffDefinition = load(LIFESTEAL)
	_check(aim != null and aim.id == &"aim_assist", "瞄准辅助定义加载", String(aim.id) if aim else "null")
	_check(steal != null and steal.id == &"lifesteal", "生命汲取定义加载", String(steal.id) if steal else "null")

	var player := _new_player(Vector2(400, 300))
	await process_frame
	var effects: StatusEffectManager = player.effects
	var stats: StatCalculator = player.stats

	# ======== 1. 各自生效 ========
	_check(is_zero_approx(player.crit_chance()), "开局暴击率为 0", str(player.crit_chance()))
	effects.apply(aim, player, -1.0)
	_check(is_equal_approx(player.crit_chance(), 0.25), "瞄准辅助把暴击率提到 0.25", str(player.crit_chance()))
	effects.apply(steal, player, 30.0)   # 给更长时长，便于观察"另一个先到期"
	_check(is_equal_approx(player.lifesteal_ratio(), 0.5), "生命汲取把吸血提到 0.5", str(player.lifesteal_ratio()))
	_check(stats.modifier_count(&"crit_chance") == 1, "暴击率只有一份修正器",
		str(stats.modifier_count(&"crit_chance")))
	_check(stats.modifier_count(&"lifesteal") == 1, "吸血只有一份修正器",
		str(stats.modifier_count(&"lifesteal")))

	# ======== 2. 一个刷新不重置另一个 ========
	effects.advance(3.0)
	var steal_before: float = effects.remaining(steal.id)
	effects.apply(aim, player, -1.0)
	_check(is_equal_approx(effects.remaining(aim.id), aim.duration), "瞄准辅助刷新回满",
		str(effects.remaining(aim.id)))
	_check(is_equal_approx(effects.remaining(steal.id), steal_before),
		"刷新瞄准辅助不动生命汲取的剩余时间",
		"%.2f vs %.2f" % [effects.remaining(steal.id), steal_before])
	_check(is_equal_approx(player.lifesteal_ratio(), 0.5), "刷新后吸血比例不变",
		str(player.lifesteal_ratio()))

	# ======== 3. 瞄准辅助过期，吸血仍在 ========
	effects.advance(aim.duration + 0.1)
	_check(not effects.has(aim.id), "瞄准辅助已过期", str(effects.has(aim.id)))
	_check(is_zero_approx(player.crit_chance()), "过期后暴击率回落到基础值",
		str(player.crit_chance()))
	_check(stats.modifier_count(&"crit_chance") == 0, "过期后暴击率修正器被撤掉",
		str(stats.modifier_count(&"crit_chance")))
	_check(effects.has(steal.id), "生命汲取仍然在", str(effects.has(steal.id)))
	_check(is_equal_approx(player.lifesteal_ratio(), 0.5), "吸血没被连带撤掉",
		str(player.lifesteal_ratio()))

	# ======== 4. 吸血真的从实际伤害回血 ========
	player.health.current = 1
	var info := DamageInfo.make(2, &"bullet", player, null, Vector2.ZERO)
	var result := DamageResult.new()
	result.info = info
	result.requested = 2
	result.hp_damage = 2
	player.on_damage_dealt(result)
	_check(player.hp == 2, "造成 2 点伤害按 50% 回 1 血", str(player.hp))
	player.on_damage_dealt(DamageResult.blocked(2, "shield", info))
	_check(player.hp == 2, "被挡下（hp_damage=0）不回血", str(player.hp))

	# ======== 5. 暴击率真的影响出弹 ========
	effects.apply(aim, player, -1.0)
	var crits := 0
	for i in range(400):
		var roll: Dictionary = player.roll_damage()
		if bool(roll["critical"]):
			crits += 1
	var ratio := float(crits) / 400.0
	_check(ratio > 0.15 and ratio < 0.36, "400 次掷骰的暴击率落在 0.25 附近",
		"%.3f" % ratio)

	# ======== 6. 胶囊真的能给到 Buff ========
	var pickup: Area2D = load(PICKUP_SCENE).instantiate()
	pickup.set("buff_definition", steal)
	pickup.set("lifetime", 5.0)
	pickup.position = Vector2(900, 300)
	_root.add_child(pickup)
	await process_frame
	effects.remove(steal.id)
	_check(not effects.has(steal.id), "先把吸血摘掉，便于验证拾取", str(effects.has(steal.id)))
	pickup._on_body_entered(player)
	await process_frame
	_check(effects.has(steal.id), "撞胶囊后获得生命汲取", str(effects.has(steal.id)))
	_check(is_equal_approx(player.lifesteal_ratio(), 0.5), "胶囊给的吸血比例正确",
		str(player.lifesteal_ratio()))

	# ======== 8. 场景里确实登记了这 5 种胶囊 ========
	var game_scene: PackedScene = load("res://scenes/game/Game.tscn")
	var game = game_scene.instantiate()
	_root.add_child(game)
	await process_frame
	var spawner = game.get_node_or_null("Spawner")
	_check(spawner != null, "Game 场景里有 Spawner 节点")
	if spawner != null:
		var ids: Array = []
		for def in spawner.pickup_effects:
			ids.append(String(def.id))
		_check(ids.has("aim_assist") and ids.has("lifesteal"),
			"Spawner 的掉落池包含两种新 Buff", str(ids))
		_check(ids.size() == 5, "掉落池共 5 种", str(ids.size()))
	game.queue_free()
	await process_frame

	# ======== 9. 死亡清空所有 Buff（放在最后：死亡会 queue_free 掉玩家） ========
	effects.apply(steal, player, 30.0)
	_check(effects.count() >= 1, "死亡前身上还有 Buff", str(effects.count()))
	player.health.current = 1
	player.get_node("Invulnerability").clear()
	player.receive_damage(DamageInfo.make(9, &"contact", null, null, player.global_position))
	# queue_free 在帧末才生效，这里同步读还安全
	_check(effects.count() == 0, "死亡后 Buff 全部移除", str(effects.count()))
	_check(stats.modifier_count(&"lifesteal") == 0, "死亡后吸血修正器清空",
		str(stats.modifier_count(&"lifesteal")))

	_finish()

func _finish() -> void:
	if is_instance_valid(_root):
		_root.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://industrial_save.json"))
	print("=== %d 项检查，%d 项失败 ===" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
