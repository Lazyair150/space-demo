extends SceneTree
# 伤害管线测试：DamageInfo → DamageReceiver → 防御组件 → Health → DamageResult。
#
# 重点不是"能不能扣血"，而是：
#   1. 请求 / 吸收 / 实际扣除三者可以分开读到；
#   2. 旧接口 take_damage(int) 与新接口结果一致（迁移期两套调用不能打架）；
#   3. 无敌、护盾这类防御规则住在受击方，不写在 Health 里；
#   4. 敌人死亡只结算一次分数。

const PLAYER_SCENE := "res://scenes/actors/Player.tscn"
const CHASER_SCENE := "res://scenes/actors/EnemyChaser.tscn"
const HASTE := "res://data/effects/haste.tres"

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

# 测试替身：吸收固定点数（用来验证"请求 10、吸收 5、实际 5"）
class HalfShield extends Node:
	@export var defense_id: StringName = &"half_shield"
	var capacity: int = 5
	func resolve_defense(info: DamageInfo) -> int:
		var take := mini(capacity, info.amount)
		capacity -= take
		return take

func _run() -> void:
	_ensure_game_state()
	_root = Node2D.new()
	_root.name = "CombatFixture"
	get_root().add_child(_root)

	# ---------- 1. 纯组件：Health + 吸收型防御 ----------
	var dummy := Node2D.new()
	dummy.name = "Dummy"
	_root.add_child(dummy)
	var health := Health.new()
	health.name = "Health"
	health.max_value = 20
	dummy.add_child(health)
	var shield := HalfShield.new()
	shield.name = "Shield"
	dummy.add_child(shield)
	var receiver := DamageReceiver.new()
	receiver.name = "Receiver"
	receiver.health_path = NodePath("../Health")
	var paths: Array[NodePath] = [NodePath("../Shield")]
	receiver.defense_paths = paths
	dummy.add_child(receiver)
	await process_frame

	_check(health.current == 20, "Health 初始化到上限", str(health.current))
	var info := DamageInfo.make(10, &"bullet", null, null, Vector2(5, 5))
	_check(info.describe().contains("10"), "DamageInfo 能描述自己", info.describe())

	var result := receiver.receive(info)
	_check(result.requested == 10, "结果保留了请求值", str(result.requested))
	_check(result.absorbed == 5, "护盾吸收 5 点", str(result.absorbed))
	_check(result.hp_damage == 5, "实际扣血 5 点", str(result.hp_damage))
	_check(health.current == 15, "生命剩 15", str(health.current))
	_check(result.blocked_by == &"half_shield", "记录是谁挡的", String(result.blocked_by))

	var second := receiver.receive(DamageInfo.make(10))
	_check(second.absorbed == 0 and second.hp_damage == 10, "护盾耗尽后不再吸收",
		"absorbed=%d hp=%d" % [second.absorbed, second.hp_damage])
	_check(health.current == 5, "生命剩 5", str(health.current))

	var old_style := receiver.take_damage(3)
	_check(old_style.hp_damage == 3 and health.current == 2, "旧接口 take_damage 走同一条管线",
		"hp_damage=%d current=%d" % [old_style.hp_damage, health.current])

	var lethal := receiver.take_damage(99)
	_check(lethal.died and health.current == 0, "致命伤害把生命打到 0 并标记 died",
		"died=%s current=%d" % [str(lethal.died), health.current])
	var overkill := receiver.take_damage(5)
	_check(overkill.blocked_by == &"dead" and overkill.hp_damage == 0, "死人不再受伤",
		String(overkill.blocked_by))

	# ---------- 2. 玩家：无敌窗口由防御组件把关 ----------
	if get_root().get_node_or_null("GameState") != null:
		get_root().get_node("GameState").score = 0
	var player: CharacterBody2D = load(PLAYER_SCENE).instantiate()
	player.position = Vector2(200, 200)
	_root.add_child(player)
	await process_frame
	player.set_physics_process(false)

	_check(player.hp == player.max_hp, "玩家血量来自 Health 组件", str(player.hp))
	_check(not player.is_invulnerable(), "开局不在无敌中")

	var hit: DamageResult = player.receive_damage(DamageInfo.make(1, &"bullet"))
	_check(hit.hp_damage == 1 and player.hp == player.max_hp - 1, "第一下正常掉血",
		"hp=%d" % player.hp)
	_check(player.is_invulnerable(), "掉血后进入无敌窗口")
	var blocked: DamageResult = player.receive_damage(DamageInfo.make(1, &"bullet"))
	_check(blocked.hp_damage == 0, "无敌期间第二下不掉血", str(blocked.hp_damage))
	_check(blocked.blocked_by == &"invuln", "并标明是被无敌挡的", String(blocked.blocked_by))

	# 毒与子弹走同一条判定：无敌期间一样被挡
	var poison: DamageResult = player.receive_damage(DamageInfo.make(1, &"poison"))
	_check(poison.hp_damage == 0 and poison.blocked_by == &"invuln", "毒也受无敌约束",
		"%s / %s" % [str(poison.hp_damage), String(poison.blocked_by)])

	player._invuln = 0.0
	var after: DamageResult = player.receive_damage(DamageInfo.make(1, &"bullet"))
	_check(after.hp_damage == 1, "无敌清零后照常掉血", str(after.hp_damage))

	# 飘字：命中后应该在父节点下留一个 Label
	var popups := 0
	for child in _root.get_children():
		if child.get_script() != null and String(child.get_script().resource_path).ends_with("FloatingDamage.gd"):
			popups += 1
	_check(popups > 0, "命中产生了飘字节点", str(popups))

	# ---------- 3. 能量盾作为防御组件接入 ----------
	player._invuln = 0.0
	var features = player.get_node("PlayerFeatures")
	var energy_shield = features.get_node("EnergyShield")
	features.set_feature_active(&"shield", true)
	_check(energy_shield.active, "能量盾可以打开")
	var hp_before: int = player.hp
	var shieldupt: DamageResult = player.receive_damage(DamageInfo.make(1, &"bullet"))
	_check(shieldupt.hp_damage == 0 and shieldupt.absorbed == 1, "护盾把这一下全挡了",
		"absorbed=%d hp=%d" % [shieldupt.absorbed, shieldupt.hp_damage])
	_check(shieldupt.blocked_by == &"shield", "记录为护盾格挡", String(shieldupt.blocked_by))
	_check(player.hp == hp_before, "被挡下时不掉血", str(player.hp))
	# 盾自己带 0.5 秒无敌（EnergyShield.block_invuln），这是盾的规则、不是管线的规则
	_check(player.is_invulnerable() and player._invuln > 0.0, "格挡后给了盾自带的短暂无敌",
		str(player._invuln))

	# ---------- 4. 敌人：死亡只结算一次 ----------
	var chaser: CharacterBody2D = load(CHASER_SCENE).instantiate()
	chaser.position = Vector2(800, 500)
	_root.add_child(chaser)
	chaser.set_physics_process(false)
	await process_frame
	var score_before: int = get_root().get_node("GameState").score
	var chaser_score: int = chaser.score_value
	var died_at: Array = []
	chaser.died.connect(func(at): died_at.append(at))
	var enemy_hit: DamageResult = chaser.receive_damage(DamageInfo.make(1, &"bullet"))
	_check(enemy_hit.hp_damage == 1 and chaser.hp == chaser.max_hp - 1, "敌人第一下掉血但不死",
		"hp=%d/%d" % [chaser.hp, chaser.max_hp])
	chaser.receive_damage(DamageInfo.make(99, &"bullet"))
	await process_frame
	_check(died_at.size() == 1, "敌人死亡只发一次 died", str(died_at.size()))
	var score_after: int = get_root().get_node("GameState").score
	_check(score_after - score_before == chaser_score, "击杀分数只结算一次",
		"%d → %d（score_value=%d）" % [score_before, score_after, chaser_score])

	_finish()

func _finish() -> void:
	if is_instance_valid(_root):
		_root.free()
	var wallet = get_root().get_node_or_null("GameState")
	if wallet != null:
		wallet.ore = 0
		wallet.materials = 0
		wallet.attack_level = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	print("=== %d 项检查，%d 项失败 ===" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
