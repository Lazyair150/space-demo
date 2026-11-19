extends SceneTree
# Buff 生命周期回归：
#   1. INDEPENDENT / KEEP_STRONGEST 只能安全退化成 REFRESH（不能建第二个同 id 实例，
#      否则 owner_key 相同会互相撤掉修正器）；
#   2. 刷新 / 叠层后定时效果必须继续触发，不能以初始时长为上限停下；
#   3. EXTEND 保留 tick 进度。
# 这些是被源码审查指出的真 bug，之前 effects_smoke 只验了"剩余时间会刷新"，没验 tick。

const STATS_SCRIPT := "res://scripts/player/stats/StatCalculator.gd"
const MANAGER_SCRIPT := "res://scripts/player/effects/StatusEffectManager.gd"
const BUFF_DEF := "res://scripts/player/effects/BuffDefinition.gd"
const HASTE_DEF := "res://data/effects/haste.tres"
const POISON_DEF := "res://data/effects/poison.tres"

var _checks := 0
var _fails := 0
var _root: Node

func _init() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("PASS %s%s" % [what, "" if detail.is_empty() else "（实际：%s）" % detail])
	else:
		_fails += 1
		print("FAIL %s%s" % [what, "" if detail.is_empty() else "（实际：%s）" % detail])

func _make_poison_instance() -> PoisonBuffInstance:
	var instance: PoisonBuffInstance = load("res://scripts/player/effects/PoisonBuffInstance.gd").new()
	return instance

func _run() -> void:
	_root = Node.new()
	_root.name = "BuffFixture"
	get_root().add_child(_root)

	var stats: StatCalculator = load(STATS_SCRIPT).new()
	_root.add_child(stats)
	var manager: StatusEffectManager = load(MANAGER_SCRIPT).new()
	_root.add_child(manager)
	manager.bind_stats(stats)

	var target := Node2D.new()
	_root.add_child(target)

	# ======== 1. INDEPENDENT 退化：不得出现第二个实例 ========
	var independent: BuffDefinition = load(BUFF_DEF).new()
	independent.id = &"test_independent"
	independent.label = "独立测试"
	independent.duration = 5.0
	independent.stack_policy = BuffDefinition.StackPolicy.INDEPENDENT
	independent.max_stacks = 3
	independent.modifiers = [{"stat": "fire_rate", "stage": 1, "value": 0.5}]

	var first := manager.apply(independent, target)
	_check(first != null, "INDEPENDENT 第一次施加成功")
	var mods_after_first := stats.modifier_count(&"fire_rate")
	manager.apply(independent, target)
	manager.apply(independent, target)
	_check(manager.count() == 1, "INDEPENDENT 重复施加不新建实例", str(manager.count()))
	_check(stats.modifier_count(&"fire_rate") == mods_after_first,
		"INDEPENDENT 重复施加不重复登记修正器",
		"%d vs %d" % [stats.modifier_count(&"fire_rate"), mods_after_first])
	_check(is_equal_approx(manager.remaining(&"test_independent"), 5.0),
		"INDEPENDENT 重复施加刷新剩余时间",
		str(manager.remaining(&"test_independent")))
	# 到期后修正器必须清空，且不影响别的 Buff
	manager.remove(&"test_independent")
	_check(stats.modifier_count(&"fire_rate") == 0, "移除后修正器清空",
		str(stats.modifier_count(&"fire_rate")))

	# ======== 2. KEEP_STRONGEST 退化：max_stacks=3 也不得叠出第二个实例 ========
	var strongest: BuffDefinition = load(BUFF_DEF).new()
	strongest.id = &"test_strongest"
	strongest.label = "最强测试"
	strongest.duration = 4.0
	strongest.stack_policy = BuffDefinition.StackPolicy.KEEP_STRONGEST
	strongest.max_stacks = 3
	strongest.modifiers = [{"stat": "speed", "stage": 1, "value": 2.0}]
	manager.apply(strongest, target)
	manager.apply(strongest, target)
	_check(manager.count() == 1, "KEEP_STRONGEST 在未满层时也不新建实例", str(manager.count()))
	_check(is_equal_approx(manager.remaining(&"test_strongest"), 4.0),
		"KEEP_STRONGEST 按刷新处理", str(manager.remaining(&"test_strongest")))
	_check(stats.modifier_count(&"speed") == 1, "KEEP_STRONGEST 只保留一份修正器",
		str(stats.modifier_count(&"speed")))
	manager.clear_all()
	_check(stats.modifier_count(&"speed") == 0, "clear_all 后修正器清空")

	# ======== 3. 中毒刷新后 tick 必须继续 ========
	var poison: BuffDefinition = load(POISON_DEF)
	var victim: Node2D = load("res://scenes/actors/Player.tscn").instantiate()
	victim.position = Vector2(500, 500)
	_root.add_child(victim)
	victim.set_physics_process(false)
	var hp_before: int = victim.max_hp

	var poison_instance: BuffInstance = manager.apply(poison, victim)
	_check(poison_instance != null, "中毒施加成功", poison.id)
	# 4 秒：每秒 1 次，但玩家有 0.8 秒无敌，实际掉血次数受无敌限制；这里用 total 计数靠 HP 观察
	for i in range(20):
		manager.advance(0.2)
	var hp_after_4s: int = victim.hp
	_check(hp_after_4s < hp_before, "中毒 4 秒内造成过伤害", "%d → %d" % [hp_before, hp_after_4s])

	# 刷新：剩余时间回满，且 tick 计时重新开始
	manager.apply(poison, victim)
	_check(is_equal_approx(manager.remaining(poison.id), poison.duration),
		"刷新后剩余时间回满", str(manager.remaining(poison.id)))
	var instance_after_refresh: BuffInstance = manager.find(poison.id)
	var tick_before: int = instance_after_refresh._ticks_fired
	# 刷新后再走 2.5 秒：必须有新的 tick（修复前 tick 会以初始 duration 为上限停住）
	for i in range(25):
		manager.advance(0.1)
	var tick_after: int = instance_after_refresh._ticks_fired
	_check(tick_after > tick_before, "刷新后定时效果继续触发",
		"%d → %d" % [tick_before, tick_after])
	_check(tick_after - tick_before >= 2, "刷新后 2.5 秒至少触发 2 次",
		str(tick_after - tick_before))

	# ======== 4. EXTEND 保留 tick 进度 ========
	var extend_def: BuffDefinition = load(BUFF_DEF).new()
	extend_def.id = &"test_extend"
	extend_def.label = "延长测试"
	extend_def.duration = 2.0
	extend_def.stack_policy = BuffDefinition.StackPolicy.EXTEND
	extend_def.tick_interval = 1.0
	extend_def.modifiers = []
	var extended: BuffInstance = manager.apply(extend_def, victim)
	manager.advance(0.5)
	var ticks_at_half: int = extended._ticks_fired
	manager.apply(extend_def, victim)
	_check(manager.count() == 2, "EXTEND 仍是同一个实例（不与中毒混）", str(manager.count()))
	_check(is_equal_approx(manager.remaining(&"test_extend"), 3.5),
		"EXTEND 增加时长而非重置", str(manager.remaining(&"test_extend")))
	_check(extended._ticks_fired == ticks_at_half, "EXTEND 不重置 tick 进度",
		str(extended._ticks_fired))
	manager.advance(0.5)
	_check(extended._ticks_fired == ticks_at_half + 1, "EXTEND 后按原进度触发 tick",
		str(extended._ticks_fired))

	# ======== 5. duration_override：一次推进超过存活时长，只按存活时长结算 ========
	var short_debuff: BuffDefinition = load(BUFF_DEF).new()
	short_debuff.id = &"test_short_poison"
	short_debuff.label = "短毒"
	short_debuff.duration = 5.0
	short_debuff.tick_interval = 1.0
	short_debuff.tick_damage = 1
	short_debuff.stack_policy = BuffDefinition.StackPolicy.REFRESH
	short_debuff.modifiers = []
	short_debuff.instance_script = load("res://scripts/player/effects/PoisonBuffInstance.gd")

	var short_target: Node2D = load("res://scenes/actors/Player.tscn").instantiate()
	short_target.position = Vector2(300, 300)
	_root.add_child(short_target)
	short_target.set_physics_process(false)
	var short_instance: BuffInstance = manager.apply(short_debuff, short_target, 1.5)
	_check(short_instance != null, "duration_override 施加成功", "1.5 秒")
	var ticks := short_instance.advance(3.0)
	_check(ticks == 1, "一次推进 3 秒但只活 1.5 秒 → 只触发 1 次", str(ticks))
	_check(is_zero_approx(short_instance.remaining), "推进超过存活时长后剩余为 0",
		str(short_instance.remaining))
	var extra := short_instance.advance(2.0)
	_check(extra == 0, "到期后继续推进不再触发", str(extra))

	_finish()

func _finish() -> void:
	if is_instance_valid(_root):
		_root.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	print("=== %d 项检查，%d 项失败 ===" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
