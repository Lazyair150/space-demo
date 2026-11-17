extends SceneTree
## S2：三张策略验证单是否真的制造了决策冲突。
##
## 这个测试不满足于"三张单都能执行"，它要在**同一份世界**里证明：
##   1. 时间取舍：长单开局不可行，等两刻仍然不可行（不是等一下就解决）；
##   2. 配置取舍：同一张单换装配台后，从"要做 1 次改形、耗 1 份蜜"变成"根本做不到"；
##   3. 资源取舍：执行一张单会让另一张单从可行变不可行（抢同一批舱段）。
## 另加一条**真实链路**的执行锁定断言（与 ui_smoke 的合成快照互补）。

const WORLD_PATH := "res://data/industrial/world_tradeoff.json"

var _runtime: Node
var _wallet: Node
var _checks := 0
var _fails := 0


func _init() -> void:
	print("=== industrial tradeoff smoke ===")
	_clean_saves()
	_wallet = get_root().get_node_or_null("GameState")
	if _wallet == null:
		_wallet = load("res://globals/GameState.gd").new()
		_wallet.name = "GameState"
		get_root().add_child(_wallet)
		# --script 环境也可能装载 autoload：无条件关闭钱包落盘，避免污染玩家存档
		_wallet.persist_wallet = false
		# --script 环境也可能装载 autoload，所以无条件关闭落盘

	_runtime = get_root().get_node_or_null("IndustrialRuntime")
	if _runtime == null:
		_runtime = load("res://scripts/industrial/runtime/IndustrialRuntime.gd").new()
		_runtime.name = "IndustrialRuntime"
		get_root().add_child(_runtime)

	var started: Dictionary = _runtime.start(WORLD_PATH, -1)
	_check(bool(started.get("success", false)), "验证世界加载成功")
	var state: Dictionary = _runtime.get_state()
	_check(int(state.get("turns", {}).get("limit", 0)) == 8, "世界是 8 回合的紧预算（时间才可能成为取舍）")
	_check(state.get("workshops", []).size() == 2, "两个装配台（主/副）")
	_check(int(state.get("level", {}).get("goalOrders", -1)) == 0, "沙盒模式：不设通关目标")
	_check(int(_runtime.get_order_templates().get("data", {}).get("templates", []).size()) == 3, "三张验证单都在配置里")

	_create_three_orders()
	_check(_runtime.get_state().get("orders", []).size() == 3, "三张单已挂到工单板")

	# ---------- 1. 时间取舍：长单不是等一两刻就好 ----------
	var long_order := _feasibility(_runtime.get_state(), 2)
	_check(not bool(long_order.get("feasible", true)), "超长线开局不可行（必须靠生产累积）")
	_check(int(long_order.get("directCount", 0)) == 0, "超长线开局直接可用 0 件")
	_runtime.set_master(0)
	for i in 2:
		_runtime.advance_manual()
	_runtime.check_all_feasibility()
	long_order = _feasibility(_runtime.get_state(), 2)
	_check(not bool(long_order.get("feasible", true)), "推两刻后超长线仍然不可行（直接可用 %d / 5）" % int(long_order.get("directCount", 0)))

	# ---------- 2. 真实链路上的执行锁定 ----------
	var long_started: Dictionary = _runtime.start_order(2)
	_check(bool(long_started.get("success", false)), "两刻后超长线可以开始（说明只是需要攒，不是死单）")
	_check(_has_active_process(_runtime.get_state()), "真实链路上确有在册过程（不是合成快照）")

	var scene = load("res://scenes/industrial/IndustrialMain.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	scene._apply_state(_runtime.get_state())
	_check(scene._master_card._pick_button.disabled, "真实过程运行中「换主台」被禁用")
	_check(scene._orders_panel._pick_template.disabled, "真实过程运行中「选模板」被禁用")
	_check(bool(scene._lines_panel._locked), "真实过程运行中产线档位与投矿被锁定")

	var process_id := 0
	for process in _runtime.get_state().get("processes", []):
		if str(process.get("kind", "")) == "order_execution":
			process_id = int(process.get("id", 0))
			break
	_runtime.cancel_process(process_id)
	scene._apply_state(_runtime.get_state())
	_check(not scene._master_card._pick_button.disabled, "取消后「换主台」恢复可用")

	# ---------- 3. 配置取舍：同一张单换台，从"要改形"变成"做不到" ----------
	_runtime.reset_world()
	_runtime.set_master(0)
	for i in 6:
		_runtime.advance_manual()
	_create_three_orders()
	_runtime.check_all_feasibility()
	state = _runtime.get_state()
	var on_master := _feasibility(state, 1)
	_check(bool(on_master.get("feasible", false)), "异形换台在启明台（三棱是附加标记）可行")
	var reshape_master := _reshape_steps(on_master)
	var liquid_master := _liquids_consumed(on_master)
	_check(reshape_master >= 1, "启明台下要改形（%d 步）" % reshape_master)
	_check(liquid_master >= 1, "启明台下改形要耗工质（%d 份）" % liquid_master)

	_runtime.set_master(1)
	_runtime.check_all_feasibility()
	var on_slave := _feasibility(_runtime.get_state(), 1)
	_check(
		(not bool(on_slave.get("feasible", true))) or _liquids_consumed(on_slave) < liquid_master,
		"换到长庚台结果不同（可行 %s，工质 %d）" % [on_slave.get("feasible", false), _liquids_consumed(on_slave)]
	)
	_runtime.set_master(0)
	_runtime.check_all_feasibility()

	# ---------- 4. 资源取舍：执行一张单会让另一张单变差 ----------
	var shared_before := _feasibility(_runtime.get_state(), 0)
	_check(bool(shared_before.get("feasible", false)), "双线争料此时可行")
	var shared_direct_before := int(shared_before.get("directCount", 0))
	_check(shared_direct_before >= 2, "双线争料已有可用的舱段（%d）" % shared_direct_before)
	var started_long: Dictionary = _runtime.start_order(2)
	_check(bool(started_long.get("success", false)), "开始超长线")
	_runtime.check_all_feasibility()
	var shared_after := _feasibility(_runtime.get_state(), 0)
	var shared_direct_after := int(shared_after.get("directCount", 0))
	_check(
		(not bool(shared_after.get("feasible", true))) or shared_direct_after < shared_direct_before,
		"执行超长线后双线争料变差（直接可用 %d → %d，可行 %s → %s）" % [
			shared_direct_before, shared_direct_after,
			shared_before.get("feasible", false), shared_after.get("feasible", false)]
	)

	# ---- 证据：把三张单的实测数字打出来（供文档引用，不是断言）----
	var evidence: Dictionary = _runtime.get_state()
	print("--- 证据：工单实测 ---")
	for order in evidence.get("orders", []):
		var result = order.get("feasibilityResult")
		if not (result is Dictionary):
			continue
		var path = _as_array(result.get("solverPath"))
		var kinds: Array[String] = []
		for step in path:
			kinds.append(str(step.get("type", "")))
		print("  单 #%d 需求 %s 件 | 可行 %s | 直接可用 %s | 步骤 %s | 工质消耗 %d" % [
			int(order.get("id", 0)), order.get("requirements", []).size(),
			result.get("feasible", false), int(result.get("directCount", 0)),
			str(kinds), _liquids_consumed(result)])
	var warehouse: Dictionary = evidence.get("warehouse", {})
	print("  仓库：舱段 %s | 工质 %s | 回合 %s/%s" % [
		int(warehouse.get("jars", 0)), str(warehouse.get("liquids", {})),
		int(evidence.get("turns", {}).get("used", 0)), int(evidence.get("turns", {}).get("limit", 0))])

	scene.queue_free()
	await process_frame
	_runtime.queue_free()
	_wallet.queue_free()
	await process_frame
	_clean_saves()

	print("=== %d 项检查，%d 项失败 ===" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)


func _create_three_orders() -> void:
	for name in ["双线争料", "异形换台", "超长线"]:
		_runtime.create_order_from_template(name)
	_runtime.check_all_feasibility()


func _feasibility(state: Dictionary, index: int) -> Dictionary:
	var orders: Array = state.get("orders", [])
	if index < 0 or index >= orders.size():
		return {}
	var result = orders[index].get("feasibilityResult")
	return result if result is Dictionary else {}


func _reshape_steps(feasibility: Dictionary) -> int:
	var count := 0
	for step in _as_array(feasibility.get("solverPath")):
		if str(step.get("type", "")) == "RESHAPE":
			count += 1
	return count


func _liquids_consumed(feasibility: Dictionary) -> int:
	var count := 0
	for step in _as_array(feasibility.get("solverPath")):
		# consumed 是"这一步实际要花什么"，costLiquid 只是它的简写；两者同时有值时不要重复计。
		var consumed = step.get("consumed")
		var counted := 0
		if consumed is Dictionary:
			for _name in consumed:
				counted += 1
		if counted > 0:
			count += counted
		elif step.get("costLiquid") != null:
			count += 1
	var transfers = feasibility.get("transferLiquids")
	if transfers is Dictionary:
		for _name in transfers:
			count += 1
	return count


func _as_array(value: Variant) -> Array:
	return value if value is Array else []


func _has_active_process(state: Dictionary) -> bool:
	for process in state.get("processes", []):
		if str(process.get("kind", "")) != "order_execution":
			continue
		if str(process.get("state", "")) in ["succeeded", "failed", "aborted"]:
			continue
		return true
	return false


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		print("  PASS  %s" % message)
	else:
		_fails += 1
		print("  FAIL  %s" % message)


func _clean_saves() -> void:
	for path in ["user://player.cfg", "user://industrial_save.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
