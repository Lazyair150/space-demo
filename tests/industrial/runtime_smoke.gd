extends SceneTree
## 工业运行时（阶段 5）的 headless 冒烟测试。
##
## 这不是游戏运行：它只验证"墙钟时间 → 逻辑刻"的换算策略与信号骨架。
## 断言的是脚本侧可测的事实（推进几次、丢弃多少刻、暂停是否真的停），不是手感。

var checks := 0
var failures: Array[String] = []

var runtime: Node
var stop_reason := ""
var last_frames := 0
var last_dropped := 0


func _initialize() -> void:
	print("=== industrial runtime smoke ===")

	runtime = load("res://scripts/industrial/runtime/IndustrialRuntime.gd").new()
	runtime.name = "IndustrialRuntime"
	root.add_child(runtime)
	# headless 没有前台窗口：关掉失焦冻结，否则一切推进都会被冻结逻辑吃掉。
	runtime.freeze_when_unfocused = false

	runtime.run_stopped.connect(func(reason: String) -> void: stop_reason = reason)
	runtime.events_arrived.connect(func(frames: Array, dropped: int) -> void:
		last_frames = frames.size()
		last_dropped = dropped)

	# 1) 启动
	var started: Dictionary = runtime.start("res://data/industrial/world_sandbox.json", 7)
	_check(bool(started["success"]), "start 成功（message=%s）" % started.get("message", ""))
	if not bool(started["success"]):
		_finish()
		return
	_check(runtime.running, "start 后 running = true")
	_check(_turn_limit() == 12, "回合上限 = 12，实际 %s" % _turn_limit())
	_check(runtime._bridge != null, "Bridge 已装配")

	# 2) 累积器：不到一刻不推进
	_check(runtime.step_wall_time(1.0) == 0, "1.0 秒不足以推进一刻")
	_check(_used() == 0, "回合仍为 0")
	_check(runtime.step_wall_time(1.0) == 1, "累计 2.0 秒推进 1 刻")
	_check(_used() == 1, "回合 = 1，实际 %s" % _used())

	# 3) 小数累积：0.9 + 0.9 + 0.3 = 2.1 → 只推进 1 刻（单帧最多 1 刻）
	runtime.step_wall_time(0.9)
	runtime.step_wall_time(0.9)
	_check(runtime.step_wall_time(0.3) == 1, "0.9+0.9+0.3 跨过一格，推进 1 刻")
	_check(_used() == 2, "回合 = 2，实际 %s" % _used())

	# 4) 长卡顿：单次调用最多推进 1 刻，超出积压按上限丢弃并上报
	var dropped_before: int = runtime.dropped_ticks
	var stepped: int = runtime.step_wall_time(30.0)
	_check(stepped == 1, "卡顿 30 秒也只推进 1 刻（实际 %s）" % stepped)
	_check(runtime.dropped_ticks > dropped_before,
		"积压被丢弃且如实上报（%s → %s）" % [dropped_before, runtime.dropped_ticks])
	_check(_used() == 3, "回合 = 3，实际 %s" % _used())

	# 5) 玩家暂停：不推进，且喂多少秒都不动
	runtime.set_user_paused(true)
	var used_paused := _used()
	_check(runtime.step_wall_time(10.0) == 0, "暂停期间不推进")
	_check(_used() == used_paused, "暂停期间回合数不变（%s）" % used_paused)
	runtime.set_user_paused(false)

	# 6) 手动推进：立刻一刻，并清掉累积器（不会下一帧再补一次）
	var used_manual := _used()
	var manual: Dictionary = runtime.advance_manual()
	_check(bool(manual["success"]), "advance_manual 成功")
	_check(_used() == used_manual + 1, "手动推进后回合 +1（%s）" % _used())
	_check(runtime.step_wall_time(0.5) == 0, "手动推进把累积器清空，0.5 秒不补推")

	# 7) 帧流：界面拿记录栏数据的那条路
	runtime.advance_manual()
	_check(last_frames > 0, "手动推进后收到表现层帧（%s 帧）" % last_frames)

	# 8) 回合耗尽：Core 拒绝推进 → 运行时停下并广播原因，不再无限重试
	var guard := 0
	while runtime.running and guard < 40:
		runtime.advance_manual()
		guard += 1
	_check(not runtime.running, "回合用尽后 running = false")
	_check(stop_reason != "", "广播了停止原因（%s）" % stop_reason)
	_check(_used() <= _turn_limit(), "回合没有越过上限（%s / %s）" % [_used(), _turn_limit()])

	# 9) 帧率无关：同样的墙钟秒数，拆成 120 个 1/60 秒的碎片推进，与一次 2.0 秒推进等价
	# 上一段可能已因目标达成/回合耗尽把 running 置 false，这里重开一局拿到干净起点
	var restarted: Dictionary = runtime.start()
	_check(bool(restarted["success"]), "重开一局便于验帧率无关性")
	runtime.auto_advance = false
	runtime.set_user_paused(false)
	var used_before_raf := _used()
	# 用 130 个 1/60 秒（≈2.17 秒）而不是正好 120 个：2.0 秒整靠浮点累加会差一点点（1.9999999999999998），
	# 那一刻不推进是正确行为，不该为凑整加 epsilon。
	for i in range(130):
		runtime.step_wall_time(1.0 / 60.0)
	_check(_used() == used_before_raf + 1,
		"130 个 1/60 秒碎片只推 1 刻（%d → %d）" % [used_before_raf, _used()])
	var used_before_one := _used()
	runtime.step_wall_time(130.0 / 60.0)
	_check(_used() == used_before_one + 1,
		"同样时长的单次推进也是 1 刻（%d → %d）" % [used_before_one, _used()])

	# 10) 停止与重开
	runtime.stop()
	_check(runtime.running == false, "stop 后 running = false")

	runtime.queue_free()
	_finish()


func _turn_limit() -> int:
	var state: Dictionary = runtime.get_state()
	var turns: Dictionary = state.get("turns", {})
	return int(turns.get("limit", -1))


func _used() -> int:
	var state: Dictionary = runtime.get_state()
	var turns: Dictionary = state.get("turns", {})
	return int(turns.get("used", -1))


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  PASS  ", label)
	else:
		failures.append(label)
		print("  FAIL  ", label)


func _finish() -> void:
	print("=== %d 项检查，%d 项失败 ===" % [checks, failures.size()])
	for item in failures:
		print("  - ", item)
	quit(0 if failures.is_empty() else 1)
