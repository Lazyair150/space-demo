extends SceneTree
# 三个扩展实验：暴击 / 吸血 / 敌人护盾。
# 目的不是加玩法，而是验证现有伤害管线够不够用：
#   1. 攻击方能否在"进入管线前"决定伤害与暴击（不改 DamageInfo 的语义）；
#   2. 攻击方能否拿到 DamageResult 并只在真实掉血时吸血；
#   3. 防御组件能否跨角色复用（不依赖 PlayerFeatures），blocked_by 是否还说得清。
# 全程不改 Health / DamageReceiver 的核心逻辑。

const PLAYER_SCENE := "res://scenes/actors/Player.tscn"
const CHASER_SCENE := "res://scenes/actors/EnemyChaser.tscn"

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

# 受击替身：可选挂防御组件
func _make_dummy(name: String, hp: int, defenses: Array) -> Node2D:
	var dummy := Node2D.new()
	dummy.name = name
	_root.add_child(dummy)
	var health := Health.new()
	health.name = "Health"
	health.max_value = hp
	dummy.add_child(health)
	var receiver := DamageReceiver.new()
	receiver.name = "Receiver"
	receiver.health_path = NodePath("../Health")
	var paths: Array[NodePath] = []
	for defense in defenses:
		dummy.add_child(defense)
		paths.append(NodePath("../%s" % defense.name))
	receiver.defense_paths = paths
	dummy.add_child(receiver)
	return dummy

func _run() -> void:
	_ensure_game_state()
	_root = Node2D.new()
	_root.name = "ExtensionsFixture"
	get_root().add_child(_root)

	var player: CharacterBody2D = load(PLAYER_SCENE).instantiate()
	player.position = Vector2(200, 300)
	_root.add_child(player)
	await process_frame
	player.set_physics_process(false)

	# ================= 阶段 1：暴击 =================
	# 必暴：伤害翻倍、标记为暴击
	player.crit_chance_base = 1.0
	player.crit_multiplier = 2.0
	var crit_roll: Dictionary = player.roll_damage()
	_check(crit_roll["critical"] == true, "暴击率 100% 时判为暴击", str(crit_roll))
	_check(int(crit_roll["amount"]) == player.attack_damage_int() * 2, "暴击伤害是基础的两倍",
		"%d vs 基础 %d" % [int(crit_roll["amount"]), player.attack_damage_int()])

	# 不暴：伤害等于基础
	player.crit_chance_base = 0.0
	var plain_roll: Dictionary = player.roll_damage()
	_check(plain_roll["critical"] == false, "暴击率 0 时判为普通")
	_check(int(plain_roll["amount"]) == player.attack_damage_int(), "普通伤害等于攻击力")

	# 子弹带上判定结果，结算时结果里能读到暴击
	player.crit_chance_base = 1.0
	player.spawn_bullet()
	await process_frame
	var bullets := []
	for child in _root.get_children():
		if String(child.get_script().resource_path).ends_with("PlayerBullet.gd"):
			bullets.append(child)
	_check(bullets.size() == 1, "开一枪生成一发子弹", str(bullets.size()))
	var bullet = bullets[0]
	_check(bullet.critical == true, "子弹带上了暴击标记")
	_check(bullet.damage == player.attack_damage_int() * 2, "子弹伤害是暴击后的值",
		str(bullet.damage))

	var crit_dummy := _make_dummy("CritDummy", 5, [])
	await process_frame
	var crit_result: DamageResult = crit_dummy.get_node("Receiver").receive(
		DamageInfo.make(bullet.damage, &"bullet", player, bullet, Vector2.ZERO, bullet.critical))
	_check(crit_result.critical == true, "结算结果记录了暴击", str(crit_result.critical))
	_check(crit_result.hp_damage == bullet.damage, "暴击按请求值扣血", str(crit_result.hp_damage))
	bullet.queue_free()
	player.crit_chance_base = 0.0

	# ================= 阶段 2：吸血 =================
	player.lifesteal_base = 1.0
	# 先把玩家打到 2 血，留出回血空间
	player.receive_damage(DamageInfo.make(1, &"bullet"))
	await process_frame
	var hp_before: int = player.hp
	_check(hp_before == player.max_hp - 1, "玩家先掉 1 血作为回血基线", str(hp_before))

	# 真实掉血 → 按实际伤害吸血
	var heal_dummy := _make_dummy("HealDummy", 5, [])
	await process_frame
	var heal_target = heal_dummy.get_node("Receiver")
	var heal_bullet = load("res://scenes/actors/PlayerBullet.tscn").instantiate()
	heal_bullet.set("damage", 1)
	heal_bullet.set("attacker", player)
	_root.add_child(heal_bullet)
	await process_frame
	heal_bullet._try_hit(heal_dummy.get_node("Receiver"))
	await process_frame
	_check(player.hp == player.max_hp, "造成 1 点真实伤害后回 1 血",
		"hp=%d" % player.hp)
	_check(heal_target.health.current == 4, "替身实际掉血 1", str(heal_target.health.current))

	# 被护盾挡下 → 不吸血
	player.health.current = 2
	var shield := ShieldCharges.new()
	shield.name = "ShieldCharges"
	shield.charges = 1
	var shielded := _make_dummy("ShieldedDummy", 5, [shield])
	await process_frame
	var shielded_result: DamageResult = shielded.get_node("Receiver").receive(
		DamageInfo.make(1, &"bullet", player, null))
	player.on_damage_dealt(shielded_result)
	_check(shielded_result.hp_damage == 0 and shielded_result.absorbed == 1,
		"护盾挡下时 hp_damage 为 0", "%d/%d" % [shielded_result.hp_damage, shielded_result.absorbed])
	_check(player.hp == 2, "护盾挡伤不吸血", str(player.hp))

	# 被无敌挡下 → 不吸血
	player.health.current = 2
	var invuln := Invulnerability.new()
	invuln.name = "Invulnerability"
	invuln.start(5.0)
	var invuln_dummy := _make_dummy("InvulnDummy", 5, [invuln])
	await process_frame
	var invuln_result: DamageResult = invuln_dummy.get_node("Receiver").receive(
		DamageInfo.make(1, &"bullet", player, null))
	player.on_damage_dealt(invuln_result)
	_check(invuln_result.hp_damage == 0 and invuln_result.blocked_by == &"invuln",
		"无敌挡下时标记为 invuln", String(invuln_result.blocked_by))
	_check(player.hp == 2, "无敌挡伤不吸血", str(player.hp))

	# 目标已死 → 不吸血
	player.health.current = 2
	var dead_dummy := _make_dummy("DeadDummy", 1, [])
	await process_frame
	var dead_receiver = dead_dummy.get_node("Receiver")
	dead_receiver.take_damage(1)
	var dead_result: DamageResult = dead_receiver.receive(DamageInfo.make(1, &"bullet", player, null))
	player.on_damage_dealt(dead_result)
	_check(dead_result.blocked_by == &"dead", "对已死目标标记为 dead", String(dead_result.blocked_by))
	_check(player.hp == 2, "目标已死时不吸血", str(player.hp))

	# 攻击者已被释放 → 不崩
	player.health.current = 2
	var ghost := CharacterBody2D.new()
	ghost.name = "GhostAttacker"
	_root.add_child(ghost)
	var ghost_bullet = load("res://scenes/actors/PlayerBullet.tscn").instantiate()
	ghost_bullet.set("damage", 1)
	ghost_bullet.set("attacker", ghost)
	_root.add_child(ghost_bullet)
	await process_frame
	ghost.free()
	ghost_bullet._try_hit(heal_dummy.get_node("Receiver"))
	_check(is_instance_valid(heal_dummy), "攻击者已释放时命中不崩", "存活=%s" % str(is_instance_valid(heal_dummy)))

	# ================= 阶段 3：敌人护盾（跨角色复用） =================
	var chaser: CharacterBody2D = load(CHASER_SCENE).instantiate()
	chaser.position = Vector2(700, 500)
	chaser.set("starting_shield", 1)
	_root.add_child(chaser)
	chaser.set_physics_process(false)
	await process_frame
	_check(chaser.get_node_or_null("ShieldCharges") != null, "追兵出生时挂上了通用护盾")

	var chaser_hp: int = chaser.hp
	var first: DamageResult = chaser.receive_damage(DamageInfo.make(1, &"bullet", player, null))
	_check(first.absorbed == 1 and first.hp_damage == 0, "第一下被护盾吸收",
		"absorbed=%d hp=%d" % [first.absorbed, first.hp_damage])
	_check(first.blocked_by == &"shield_charges", "记录为次数护盾", String(first.blocked_by))
	_check(chaser.hp == chaser_hp, "被吸收时不掉血", str(chaser.hp))
	var second: DamageResult = chaser.receive_damage(DamageInfo.make(1, &"bullet", player, null))
	_check(second.hp_damage == 1 and chaser.hp == chaser_hp - 1, "护盾用完后再打就掉血",
		"hp=%d" % chaser.hp)

	# 无敌 + 次数护盾同时存在时，blocked_by 是否说得清
	var both_invuln := Invulnerability.new()
	both_invuln.name = "Invulnerability"
	both_invuln.start(5.0)
	var both_shield := ShieldCharges.new()
	both_shield.name = "ShieldCharges"
	both_shield.charges = 1
	var both_dummy := _make_dummy("BothDummy", 5, [both_invuln, both_shield])
	await process_frame
	var both_receiver = both_dummy.get_node("Receiver")
	var blocked: DamageResult = both_receiver.receive(DamageInfo.make(1, &"bullet", player, null))
	_check(blocked.blocked_by == &"invuln", "两个防御并存时先报无敌", String(blocked.blocked_by))
	_check(both_shield.remaining() == 1, "被无敌挡下时不消耗护盾次数", str(both_shield.remaining()))
	both_invuln.clear()
	var after_invuln: DamageResult = both_receiver.receive(DamageInfo.make(1, &"bullet", player, null))
	_check(after_invuln.blocked_by == &"shield_charges", "无敌结束后由护盾接管",
		String(after_invuln.blocked_by))
	_check(both_shield.remaining() == 0, "这次消耗掉护盾次数", str(both_shield.remaining()))

	# 非玩家个体也能直接用同一个组件（不依赖 PlayerFeatures）
	var plain := _make_dummy("PlainDummy", 3, [])
	await process_frame
	var plain_shield := ShieldCharges.new()
	plain_shield.name = "ExtraShield"
	plain_shield.charges = 1
	plain.add_child(plain_shield)
	plain.get_node("Receiver").defenses.append(plain_shield)
	var plain_result: DamageResult = plain.get_node("Receiver").receive(
		DamageInfo.make(1, &"bullet", null, null))
	_check(plain_result.absorbed == 1, "任意节点都能用同一个护盾组件", str(plain_result.absorbed))

	# ================= 阶段 4：已释放实例不再炸（回归 m02482 报的错） =================
	# 射手被打死、它发出的子弹还在飞，命中时 attacker 已经是"已释放实例"。
	var doomed := Node2D.new()
	doomed.name = "DoomedShooter"
	_root.add_child(doomed)
	await process_frame
	doomed.free()
	var tolerant := DamageInfo.make(1, &"bullet", doomed, doomed, Vector2.ZERO)
	_check(tolerant.attacker == null, "已释放的攻击者被降级成空", str(tolerant.attacker))
	_check(tolerant.source == null, "已释放的载体被降级成空", str(tolerant.source))

	player.health.current = player.max_hp
	# 前面几段挨过打，无敌帧可能还在；这里先清掉，单独验证"敌弹能命中"
	player.get_node("Invulnerability").clear()
	var live_dummy := _make_dummy("LiveDummy", 5, [])
	await process_frame
	var enemy_bullet = load("res://scenes/actors/EnemyBullet.tscn").instantiate()
	enemy_bullet.set("damage", 1)
	enemy_bullet.set("attacker", doomed)
	_root.add_child(enemy_bullet)
	await process_frame
	enemy_bullet._on_body_entered(player)
	await process_frame
	_check(player.hp == player.max_hp - 1, "攻击者已释放的敌弹照样能打中",
		"hp=%d" % player.hp)

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
