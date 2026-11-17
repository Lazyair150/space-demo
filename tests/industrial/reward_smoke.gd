extends SceneTree
## 阶段 10 冒烟测试：工单结算 → 强化材料 → 舰船攻击力。
##
## 关注三件事：
## 1. 同一张工单只发一次奖（账本幂等）；
## 2. 材料能换攻击力，且材料不够/到顶时什么都不改；
## 3. 重开一局后同一张工单还能拿奖（账本随局面清空）。

var _checks := 0
var _failed := 0
var _runtime: Node
var _wallet: Node

func _initialize() -> void:
	_boot()
	await process_frame
	_run()
	_finish()

func _boot() -> void:
	# 每个测试自己清掉玩家存档：否则上一次跑留下的钱包/工业存档会把断言带偏（实测踩过）。
	for path in ["user://player.cfg", "user://industrial_save.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if get_root().has_node("GameState"):
		_wallet = get_root().get_node("GameState")
	else:
		_wallet = load("res://globals/GameState.gd").new()
		_wallet.name = "GameState"
		get_root().add_child(_wallet)
		# --script 环境也可能装载 autoload：无条件关闭钱包落盘，避免污染玩家存档
		_wallet.persist_wallet = false

	_runtime = get_root().get_node_or_null("IndustrialRuntime")
	if _runtime == null:
		_runtime = load("res://scripts/industrial/runtime/IndustrialRuntime.gd").new()
		_runtime.name = "IndustrialRuntime"
		get_root().add_child(_runtime)
	_runtime.auto_advance = false
	_runtime.freeze_when_unfocused = false

func _run() -> void:
	var started: Dictionary = _runtime.start()
	_check(bool(started["success"]), "工业世界装配成功（%s）" % started.get("message", ""))
	if not bool(started["success"]):
		return

	# 副舱工单（B 类，只要一只三棱舱段）开局就满足，start_order 会一次跑完。
	var templates: Dictionary = _runtime.get_order_templates()
	var names: Array = []
	for t in templates["data"]["templates"]:
		names.append(str(t["name"]))

	_check(_wallet.materials == 0, "开局没有强化材料")
	_check(_wallet.attack_damage() == 1, "开局子弹伤害是基础值 1")

	var order_id := _complete_first_order()
	_check(order_id > 0, "有一张工单被结算（id=%d）" % order_id)
	_check(_wallet.materials == 1, "结算一张工单得到 1 张强化材料（实际 %d）" % _wallet.materials)

	# 幂等：反复刷新快照（界面每次重画都会刷新）不应该再发一次。
	_runtime._refresh_state()
	_runtime._refresh_state()
	_check(_wallet.materials == 1, "重复刷新不重复发奖（实际 %d）" % _wallet.materials)

	# 材料不够时升级失败且数值不变。
	_check(not _wallet.upgrade_attack(), "材料只有 1 张时升级失败")
	_check(_wallet.attack_level == 0 and _wallet.attack_damage() == 1, "升级失败不改任何数值")

	# 补足材料再升级：3 张换 1 级、伤害 +1。
	_wallet.add_material(2)
	_check(_wallet.upgrade_attack(), "材料 3 张时升级成功")
	_check(_wallet.attack_level == 1, "攻击力等级 0 → 1")
	_check(_wallet.attack_damage() == 2, "子弹伤害 1 → 2")
	_check(_wallet.materials == 0, "升级花掉 3 张材料（实际剩 %d）" % _wallet.materials)

	# 到顶：MAX_ATTACK_LEVEL = 5，第 6 次必须失败。
	_wallet.add_material(30)
	for i in 5:
		_wallet.upgrade_attack()
	_check(_wallet.attack_level == 5, "连升到上限 5 级（实际 %d）" % _wallet.attack_level)
	_check(not _wallet.upgrade_attack(), "到顶后升级失败")
	_check(_wallet.attack_damage() == 6, "满级子弹伤害 6（实际 %d）" % _wallet.attack_damage())

	# 重开一局：账本清空，同一张工单还能拿奖。
	var before: int = _wallet.materials
	_runtime.reset_world()
	var again := _complete_first_order()
	_check(again > 0, "重开后又能结算一张工单")
	_check(_wallet.materials == before + 1, "重开后同一张工单仍能发奖（%d → %d）" % [before, _wallet.materials])

func _complete_first_order() -> int:
	# 副舱工单是 B 类（要主台 + 从台），先把台位摆好；不摆的话 start_order 会被可行性挡住。
	_runtime.set_master(0)
	_runtime.set_slave(1)
	# 先让产线把原料送进仓库、再由流入把舱段搬进主台，否则工单一派下来就没路可走。
	for i in 4:
		_runtime.advance_manual()
	# 用模板派单：优先挑"开局就满足"的副舱工单，它一步到底。
	var created: Dictionary = _runtime.create_order_from_template("双圆工单")
	if not bool(created["success"]):
		created = _runtime.create_random_order()
		if not bool(created["success"]):
			return -1
	var state: Dictionary = _runtime.get_state()
	var order_id := -1
	for order in state.get("orders", []):
		if str(order.get("status", "")) == "待执行":
			order_id = int(order.get("id", -1))
	_runtime.check_all_feasibility()
	var started: Dictionary = _runtime.start_order(0)
	if not bool(started["success"]):
		print("    [debug] start_order 失败：%s" % started.get("message", ""))
		return -1

	# 副舱工单要先把三棱舱段挪到副台/整形成三棱，一步一个逻辑刻（每 2 刻一个单位），
	# 所以这单不是"点完就成功"，得真推几刻；推到没有"执行中"的单为止。
	for i in 12:
		if not _has_executing_order():
			break
		_runtime.advance_manual()
	return order_id

func _has_executing_order() -> bool:
	for order in _runtime.get_state().get("orders", []):
		if str(order.get("status", "")) == "执行中":
			return true
	return false

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)

func _finish() -> void:
	if _runtime != null:
		_runtime.free()
	print("=== %d 项检查，%d 项失败 ===" % [_checks, _failed])
	quit(0 if _failed == 0 else 1)
