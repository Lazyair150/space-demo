extends SceneTree

## 阶段 4 的桥接冒烟测试（不参与游戏运行，只用于验证 JarCoreBridge 是否真的可用）。
##
## 用法：
##   godot --headless --path . --script res://tests/industrial/bridge_smoke.gd
##
## 注意两件事（都是实测踩到的）：
## 1) 这里**不按类型名引用** JarCoreBridge，而是 load 它的脚本再 new —— GDScript 的编译期
##    全局类表不含 C# 的 [GlobalClass] 类型，直接写类型名会 Parse Error。
## 2) 订单状态是**中文**（待执行/执行中/成功/失败，见 Core 的 Constants.OrderStatus），
##    不是 Web 页面里写死的 'success'/'failed'。

const WORLD_PATH := "res://data/industrial/world_sandbox.json"
const BRIDGE_SCRIPT := "res://scripts/industrial/bridge/JarCoreBridge.cs"

## 与 Core 的 Constants.OrderStatus 逐字一致（不要改成英文）。
const STATUS_SUCCESS := "成功"
const STATUS_FAILED := "失败"

var _failures: Array[String] = []
var _checks := 0
var _bridge


func _initialize() -> void:
	print("=== industrial bridge smoke ===")

	var world_json := FileAccess.get_file_as_string(WORLD_PATH)
	if world_json.is_empty():
		_fail("读不到世界配置：%s" % WORLD_PATH)
		_finish()
		return

	var bridge_script: Script = load(BRIDGE_SCRIPT)
	if bridge_script == null:
		_fail("加载不到桥接脚本：%s" % BRIDGE_SCRIPT)
		_finish()
		return
	_bridge = bridge_script.new()
	if _bridge == null:
		_fail("桥接脚本 new() 失败：%s" % BRIDGE_SCRIPT)
		_finish()
		return

	print("初始化前 is_ready() = ", _bridge.is_ready())

	# 1) 初始化
	var init: Dictionary = _bridge.initialize(world_json, 7)
	_check(bool(init["success"]), "initialize 成功（message=%s）" % init["message"])
	if not bool(init["success"]):
		_finish()
		return
	_check(str(init.get("error_code", "")) == "", "成功时 error_code 为空")
	_check(bool(_bridge.is_ready()), "初始化后 is_ready() = true")

	# 2) 坏配置不能污染已装配的世界
	var bad: Dictionary = _bridge.initialize("{ \"shapes\": 1 }", 7)
	_check(not bool(bad["success"]), "坏配置被拒绝（error_code=%s）" % bad["error_code"])
	_check(bool(_bridge.is_ready()), "坏配置之后世界仍然可用")

	# 3) 状态与词表：turnLimit 来自世界配置，不是界面
	var state := _data(_bridge.get_state())
	var turns: Dictionary = state["turns"]
	_check(int(turns["limit"]) == 12, "回合上限 = 12，实际 %s" % turns["limit"])
	_check((state["workshops"] as Array).size() == 2, "装配台数量 = 2")

	var meta := _data(_bridge.get_world_meta())
	_check((meta["shapes"] as Array).size() == 4, "词表形状数 = 4")
	_check((meta["liquids"] as Array).size() == 2, "词表液体数 = 2（Core 要求恰好两种）")

	# 4) 主从台位
	var templates := _data(_bridge.get_order_templates())
	_check((templates["templates"] as Array).size() == 5, "世界配置里的工单模板 = 5 张（阶段 7 的派单来源）")
	_check(str(((templates["templates"] as Array)[0] as Dictionary).get("name", "")) == "双圆工单",
		"模板按配置顺序给出（首张 = 双圆工单）")

	_check(bool(_bridge.set_master(0)["success"]), "set_master(0) 成功")
	_check(bool(_bridge.set_slave(1)["success"]), "set_slave(1) 成功")
	state = _data(_bridge.get_state())
	var global: Dictionary = state["globalState"]
	_check(int(global["currentMaster"]) == 0, "currentMaster = 0")
	_check(int(global["currentSlave"]) == 1, "currentSlave = 1")

	# 5) 预热 4 回合：产线把舱段做进仓库，流入再把它搬上主装配台
	_check(bool(_bridge.tick(4)["success"]), "预热 tick(4) 成功")
	state = _data(_bridge.get_state())
	var bench_jars: int = (state["workshops"][0]["jars"] as Array).size()
	_check(bench_jars > 0, "主装配台上有舱段（%s 只）" % bench_jars)

	# 6) 按模板派单，挑第一个**能做成**的工单（顺带验证可行性真的由 Core 判定）
	var feasible_index := -1
	var feasible_result := {}
	for template_name in ["副舱工单", "装液工单", "双圆工单", "改形工单"]:
		var created: Dictionary = _bridge.create_order_from_template(template_name)
		if not bool(created["success"]):
			_fail("模板派单失败 %s：%s" % [template_name, created["message"]])
			continue
		var order_index := _last_order_index()
		var feas: Dictionary = _bridge.check_feasibility(order_index)
		if not bool(feas["success"]):
			_fail("可行性分析失败 %s：%s" % [template_name, feas["message"]])
			continue
		var result: Dictionary = feas["data"]
		print("  %s → feasible=%s，直接可做 %s 件" % [template_name, result["feasible"], result["directCount"]])
		if bool(result["feasible"]) and feasible_index < 0:
			feasible_index = order_index
			feasible_result = result
	_check(feasible_index >= 0, "至少有一张模板工单是可行的（否则这关无解）")
	if feasible_index < 0:
		_finish()
		return
	_check(feasible_result.has("solverPath"), "可行结果含 solverPath（玩家要看见做法）")

	# 7) 开始执行 → 过程出现 → 一回合后仍在推进
	var started: Dictionary = _bridge.start_order(feasible_index)
	_check(bool(started["success"]), "start_order 成功（message=%s）" % started["message"])
	if not bool(started["success"]):
		_finish()
		return
	var process_id := int(started["data"]["processId"])
	_check(process_id > 0, "拿到 processId（%s）" % process_id)

	state = _data(_bridge.get_state())
	_check((state["processes"] as Array).size() == 1, "执行中的过程数 = 1")
	var proc_subject := "order"
	var proc_subject_id := 0
	if (state["processes"] as Array).size() == 1:
		var proc_before: Dictionary = state["processes"][0]
		proc_subject = str(proc_before["subject"])
		proc_subject_id = int(proc_before["subjectId"])

	# 8) 表现层帧流：一次 tick 里过程就可能整个跑完，所以"过程可见"必须靠帧流当场带出的日志快照
	#    （tick 返回后再查 get_steps 会因主体映射被淘汰而拿到 0 条，那是"没有保留的步骤"）。
	var steps_seen := 0
	var frame_count := 0
	for i in range(3):
		if not bool(_bridge.tick(1)["success"]):
			break
		var polled := _data(_bridge.poll_events())
		if not polled.has("frames"):
			_fail("poll_events 返回里没有 frames：%s" % str(polled))
			break
		var frames: Array = polled["frames"]
		frame_count += frames.size()
		for frame in frames:
			if frame.has("steps") and (frame["steps"] as Array).size() > steps_seen:
				steps_seen = (frame["steps"] as Array).size()
		if steps_seen > 0:
			break
	print("  帧流：累计 %s 帧，过程日志最多 %s 条" % [frame_count, steps_seen])
	_check(frame_count > 0, "tick 之后能取到表现层帧（%s 帧）" % frame_count)
	_check(steps_seen > 0, "帧里带着过程日志快照（最多 %s 条）" % steps_seen)

	var used_after_one: int = _turns_used()
	print("  用过的回合 = ", used_after_one)

	# 9) 一直推到这一单结算（同一单只结算一次）
	var status := ""
	for i in range(8):
		state = _data(_bridge.get_state())
		status = _order_status(state, feasible_index)
		if status == STATUS_SUCCESS or status == STATUS_FAILED:
			break
		if not bool(_bridge.tick(1)["success"]):
			break
	state = _data(_bridge.get_state())
	status = _order_status(state, feasible_index)
	_check(status == STATUS_SUCCESS, "工单结算为「%s」（实际「%s」）" % [STATUS_SUCCESS, status])
	_check(_turns_used() <= 12, "总回合未超过上限（%s）" % _turns_used())

	# 10) 暂停期间推进不生效（不推进、不产出的真实语义）
	_check(bool(_bridge.pause_time()["success"]), "pause_time 成功")
	var before := _turns_used()
	_check(bool(_bridge.tick(1)["success"]), "暂停期间 tick 不报错")
	_check(_turns_used() == before, "暂停期间回合数不变（%s）" % before)
	_check(bool(_bridge.resume_time()["success"]), "resume_time 成功")

	# 11) 越界意图被拒绝：回合上限是硬约束
	var over: Dictionary = _bridge.tick(50)
	_check(not bool(over["success"]), "超出回合上限被拒绝（error_code=%s）" % over["error_code"])
	_check(str(over["error_code"]) == "illegal_state", "超限归为 illegal_state")

	# 12) 未登记液体被拒绝（不崩、不静默）
	var badliquid: Dictionary = _bridge.update_liquid_rate("不存在的液体", 1.0)
	_check(not bool(badliquid["success"]), "未知液体被拒绝（error_code=%s）" % badliquid["error_code"])

	# 13) 重置回到开局
	_check(bool(_bridge.reset_world()["success"]), "reset_world 成功")
	_check(_turns_used() == 0, "重置后已用回合 = 0")

	_finish()


func _last_order_index() -> int:
	var state := _data(_bridge.get_state())
	var orders: Array = state["orders"]
	return orders.size() - 1


func _order_status(state: Dictionary, index: int) -> String:
	var orders: Array = state["orders"]
	if index < 0 or index >= orders.size():
		return ""
	return str(orders[index]["status"])


func _turns_used() -> int:
	var state := _data(_bridge.get_state())
	var turns: Dictionary = state["turns"]
	return int(turns["used"])


func _data(envelope: Dictionary) -> Dictionary:
	if not bool(envelope.get("success", false)):
		_fail("信封失败：%s（%s）" % [envelope.get("message", ""), envelope.get("error_code", "")])
		return {}
	var value: Variant = envelope.get("data", null)
	return value if value is Dictionary else {}


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  PASS  ", label)
	else:
		_fail(label)


func _fail(label: String) -> void:
	print("  FAIL  ", label)
	_failures.append(label)


func _finish() -> void:
	print("=== %d 项检查，%d 项失败 ===" % [_checks, _failures.size()])
	for item in _failures:
		print("  - ", item)
	if _bridge != null and is_instance_valid(_bridge):
		_bridge.free()
		_bridge = null
	quit(0 if _failures.is_empty() else 1)
