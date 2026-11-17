extends Node
## 工业系统的运行时（阶段 5 产物）。
##
## 职责：**决定工业世界的逻辑时间怎么走**，并把 Bridge 的结果广播给界面。
## 它是唯一持有 `JarCoreBridge` 的地方；界面只连它的信号，不自己调 Bridge 的写方法。
##
## 边界（指导书硬规则）：
## - 不实现任何工业规则：回合预算、可行性、搬运、产出全部由 Core 判定，这里只转手。
## - 不拥有世界状态：状态的唯一真相在 Core 里；本节点只缓存最近一次快照给界面画图用。
## - 不用 Godot 帧当工业 tick：帧只用来**累积墙钟时间**，逻辑刻由 `TICK_SECONDS` 换算。
##
## 时间策略（2026-11-17 用户确认"按推荐来"）：
## 1. **单帧最多推进 1 刻**。一次推进多刻时 `RunCallBoundary`（仓库→主台流入）只在调用边界发生，
##    玩家看到的物资节奏会和逐刻推进不一致，所以宁可慢也不合批。
## 2. **积压有上限**（`MAX_BACKLOG_TICKS`）。卡顿/最小化回来后不无限追帧：超出部分直接丢弃，
##    并把丢弃数如实上报（`dropped_ticks` + `ticks_dropped` 信号），绝不静默。
## 3. **失焦即冻结**（`freeze_when_unfocused`）。切出去时既不积累也不补算 ——
##    工业世界是"玩家在场才生产"，与"关闭期间不生产"同一条口径。
##
## 阶段 5 只提供时间与信号骨架；界面在阶段 6 接。

const DEFAULT_WORLD_PATH := "res://data/industrial/world_sandbox.json"

## 存档位置：整局工业世界（配置 + 种子 + 命令日志）与玩家钱包都在这里。
## 存档是**文本 JSON**：出问题时玩家/开发者能直接打开看，不用猜。
const SAVE_PATH := "user://industrial_save.json"
const SAVE_VERSION := 1

## 一张工单结算成"成功"时发多少强化材料。
const REWARD_PER_ORDER := 1

## 工单状态里的成功是中文常量（Core 的 `OrderStatus.SUCCESS`），不是 "success"。
const ORDER_STATUS_SUCCESS := "成功"

## 一个逻辑刻等于多少墙钟秒。与 Web 调试页的 `TickIntervalMs = 2000` 同值，改它只改节奏、不改判定。
const TICK_SECONDS := 2.0

## 允许积压的刻数上限：超过就丢弃，不做无限补算。
const MAX_BACKLOG_TICKS := 2

signal state_changed(state: Dictionary)
signal events_arrived(frames: Array, dropped: int)
signal turn_advanced(used: int, limit: int)
signal error_occurred(code: String, message: String)
signal run_stopped(reason: String)
signal ticks_dropped(count: int)
signal reward_earned(order_id: int, amount: int)

## 工业世界是否在走时（`start` 之后为 true；回合耗尽/手动停止后为 false）。
var running := false
## 是否按墙钟自动推进（默认关：让玩家先手动按一次「推进一回合」，理解一回合是什么）。
## 它只控制"要不要自己走"，不改任何判定 —— 与 Web 的 startTick/stopTick 同义。
var auto_advance := false
## 玩家主动暂停（与失焦冻结不同：这会同时冻结 Core 的逻辑时间）。
var user_paused := false
## 失焦时是否冻结（默认冻结；见文件头第 3 条）。
var freeze_when_unfocused := true
## 因积压上限被丢弃的逻辑刻总数（只在卡顿后增长；界面应如实显示）。
var dropped_ticks := 0

## 已经发过奖的工单 id。**账本放在运行时、不放在 GameState**：它只对"这一局工业世界"有效，
## 重开/换世界时清空，`GameState` 只当一个纯粹的玩家钱包。
var _awarded_orders := {}

var _bridge: Node
var _accumulator := 0.0
var _state: Dictionary = {}
var _world_path := DEFAULT_WORLD_PATH
var _seed := -1

## 退出时落盘：这是"关闭期间不生产"的另一半——关掉时不模拟，只把现场存下来。
func _exit_tree() -> void:
	if _bridge != null:
		save_game()

# ----------------------------------------------------------------------
# 生命周期
# ----------------------------------------------------------------------

## 装配并开始走时。`world_path` 是 `res://` 下的世界配置；`seed` 传负数表示不固定随机种子。
## 返回 { success, message, error_code }，与 Bridge 同形（界面不必区分两层）。
func start(world_path: String = DEFAULT_WORLD_PATH, seed_value: int = -1) -> Dictionary:
	if running:
		return _fail("illegal_state", "工业世界已经在运行，先 stop() 再开始")
	if _bridge == null:
		_bridge = load("res://scripts/industrial/bridge/JarCoreBridge.cs").new()
		_bridge.name = "JarCoreBridge"
		add_child(_bridge)

	var text := FileAccess.get_file_as_string(world_path)
	if text.is_empty():
		return _fail("invalid_config", "读不到世界配置：%s" % world_path)

	var envelope: Dictionary = _bridge.initialize(text, seed_value)
	if not bool(envelope.get("success", false)):
		return envelope

	_world_path = world_path
	_seed = seed_value
	_accumulator = 0.0
	dropped_ticks = 0
	user_paused = false
	# 新的一局：发奖账本必须清空，否则重开后的同号工单会被当成"已经发过"。
	_awarded_orders = {}
	running = true

	_refresh_state()
	return {"success": true, "message": "", "error_code": ""}

## 停止走时（不销毁世界：进程/订单还在，重新 start 会重开一局）。
func stop() -> void:
	if not running:
		return
	running = false
	run_stopped.emit("stopped")

# ----------------------------------------------------------------------
# 时间推进（阶段 5 的核心）
# ----------------------------------------------------------------------

## 喂一段墙钟时间：必要时推进**一个**逻辑刻。`_process` 每帧调用它；测试也直接调它。
## 返回本次实际推进的刻数（0 或 1）。
func step_wall_time(delta: float) -> int:
	if not running:
		return 0
	if user_paused:
		return 0
	if freeze_when_unfocused and not DisplayServer.window_is_focused():
		return 0

	_accumulator += maxf(delta, 0.0)

	# 先按上限截断积压：卡顿十秒回来不该真的补十秒，否则世界会瞬移。
	var cap := TICK_SECONDS * MAX_BACKLOG_TICKS
	if _accumulator > cap:
		var dropped := int(floor(_accumulator / TICK_SECONDS)) - MAX_BACKLOG_TICKS
		if dropped > 0:
			dropped_ticks += dropped
			_accumulator -= dropped * TICK_SECONDS
			ticks_dropped.emit(dropped)

	if _accumulator < TICK_SECONDS:
		return 0

	_accumulator -= TICK_SECONDS
	return 1 if _apply_tick(1) else 0

## 玩家点"推进一回合"：立刻推一刻，并把累积器清掉（避免下一帧又自动推一次）。
## 返回 { success, message, error_code }。
func advance_manual() -> Dictionary:
	if not running:
		return _fail("not_initialized", "工业世界还没开始")
	_accumulator = 0.0
	return _tick_once()

func set_user_paused(value: bool) -> void:
	if not running or user_paused == value:
		return
	user_paused = value
	if value:
		_bridge.pause_time()
	else:
		_bridge.resume_time()

## 界面打开时调一次：已装配就直接用，没装配才装配。
## 它只为"打开面板"服务，不决定世界的生命周期（世界的开关在 Runtime 自己手里）。
func ensure_started(world_path: String = DEFAULT_WORLD_PATH, seed_value: int = -1) -> Dictionary:
	if running:
		return {"success": true, "message": "", "error_code": ""}
	# 有存档就接着上一局；读档失败（存档坏了/版本不对）就当场开新局，并把原因带回去让界面提示。
	if has_save():
		var loaded := load_game()
		if bool(loaded.get("success", false)):
			return loaded
		var fresh := start(world_path, seed_value)
		fresh["message"] = "存档没读成（%s），已开新一局" % str(loaded.get("message", ""))
		return fresh
	return start(world_path, seed_value)

# ----------------------------------------------------------------------
# 写：界面 → 世界的统一出口
# ----------------------------------------------------------------------
#
# 约定（与 03 号文档 §4 一致）：
# - 界面永远不直接碰 Bridge，只调这里的转发函数；
# - 成功即重拉一次快照并广播 state_changed，界面只负责重画；
# - 失败原样返回信封，由界面弹 Toast，这里不额外发 error 信号（避免同一条错误报两次）。

## 换主装配台。
func set_master(index: int) -> Dictionary:
	return _write("set_master", [index])

## 换副装配台；`index` 传负数表示撤掉副台。
func set_slave(index: int) -> Dictionary:
	return _write("set_slave", [index])

## 随机派一张工单。
func create_random_order() -> Dictionary:
	return _write("create_random_order", [])

## 按世界配置里的模板派单（模板名来自 `get_order_templates()`）。
func create_order_from_template(template_name: String) -> Dictionary:
	return _write("create_order_from_template", [template_name])

## 世界配置声明的工单模板清单（读操作，返回 `{templates:[{name,type,requirements}]}`）。
func get_order_templates() -> Dictionary:
	if _bridge == null:
		return {"success": false, "message": "尚未初始化", "error_code": "not_initialized", "data": null}
	return _bridge.get_order_templates()

## 删除工单（按列表序号）。
func delete_order(index: int) -> Dictionary:
	return _write("delete_order", [index])

## 检查单张工单的可行性。
func check_feasibility(order_index: int) -> Dictionary:
	return _write("check_feasibility", [order_index])

## 全量检查可行性。
func check_all_feasibility() -> Dictionary:
	return _write("check_all_feasibility", [])

## 开始执行工单（异步轨：之后由逻辑刻一步步推进）。
func start_order(order_index: int) -> Dictionary:
	return _write("start_order", [order_index])

## 取消一个进行中的过程（已投入的资源不回滚，这是 Core 的语义）。
func cancel_process(process_id: int) -> Dictionary:
	return _write("cancel_process", [process_id])

## 调某条产线的速率（生产者 × 形状）。
func update_producer_rate(producer_name: String, shape: String, rate: float) -> Dictionary:
	return _write("update_producer_rate", [producer_name, shape, rate])

## 调某种液体的自产速率。
func update_liquid_rate(liquid: String, rate: float) -> Dictionary:
	return _write("update_liquid_rate", [liquid, rate])

## 重开本局（世界回开局；订单按配置重新派生）。
func reset_world() -> Dictionary:
	var envelope: Dictionary = _write("reset_world", [])
	if bool(envelope.get("success", false)):
		_accumulator = 0.0
		# 本关重来：工单 id 会从头开始，账本跟着清，新一局还是能拿到奖励。
		_awarded_orders = {}
	return envelope

# ----------------------------------------------------------------------
# 读：状态与帧流
# ----------------------------------------------------------------------

func get_state() -> Dictionary:
	return _state

# ----------------------------------------------------------------------
# 存档 / 读档
# ----------------------------------------------------------------------

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## 把"这一局工业世界"和"玩家钱包"写成一份存档。
## 工业世界存的是 Core 的意图日志（配置 + 种子 + 命令序），钱包是三个整数。
func save_game() -> Dictionary:
	# 只要世界装配过就存得下：即使这一局已经结算（running=false），现场仍然要留住。
	if _bridge == null:
		return {"success": false, "message": "工业世界还没装配，没有可保存的东西", "error_code": "not_initialized"}

	# 工业世界存成**原始 JSON 文本**（不经 Variant：Godot 会把整数读成 float，回放时 int 字段就废了）。
	var industrial_json: String = _bridge.save_state_json()
	if industrial_json.is_empty():
		return _fail("internal", "世界状态导出失败，没有可保存的东西")

	var payload := {
		"version": SAVE_VERSION,
		"world_path": _world_path,
		"accumulator": _accumulator,
		"industrial_json": industrial_json,
		"wallet": _wallet_snapshot(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return _fail("internal", "写不进存档：%s" % SAVE_PATH)
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	print("[industrial] 存档已写入 %s（命令 %d 条）" % [SAVE_PATH, _command_count(industrial_json)])

	# 钱包自己也有落盘（战斗里就可能有变化），这里顺手让它同步一次。
	var wallet := get_node_or_null("/root/GameState")
	if wallet != null and wallet.has_method("save_wallet"):
		wallet.save_wallet()
	return {"success": true, "message": "已保存", "error_code": "", "data": {"path": SAVE_PATH}}


## 读档并让世界回到存档那一刻。读不到/存档坏了都回 success=false，调用方可以退回"新开一局"。
func load_game() -> Dictionary:
	if not has_save():
		return {"success": false, "message": "还没有存档", "error_code": "invalid_arg"}
	if _bridge == null:
		_bridge = load("res://scripts/industrial/bridge/JarCoreBridge.cs").new()
		_bridge.name = "JarCoreBridge"
		add_child(_bridge)

	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var json := JSON.new()
	if json.parse(text) != OK:
		# 用 JSON.new().parse 而不是 JSON.parse_string：后者失败时会在日志里打一条引擎级 ERROR，
		# 而"玩家存档坏了"是预期内的分支，不该污染错误日志。
		return _fail("invalid_config", "存档不是合法的 JSON 对象：%s（第 %d 行）" % [SAVE_PATH, json.get_error_line()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _fail("invalid_config", "存档不是 JSON 对象：%s" % SAVE_PATH)
	var payload: Dictionary = json.data
	if int(payload.get("version", 0)) != SAVE_VERSION:
		return _fail("invalid_config", "存档版本不认识：%s（当前 %d）" % [str(payload.get("version")), SAVE_VERSION])

	var restored: Dictionary = _bridge.restore_state(str(payload.get("industrial_json", "")))
	if not bool(restored.get("success", false)):
		return restored

	_world_path = str(payload.get("world_path", DEFAULT_WORLD_PATH))
	_accumulator = float(payload.get("accumulator", 0.0))
	# 读回来的世界不等于"在走时"：玩家还没按推进，自动推进也还关着。
	user_paused = false
	_awarded_orders = {}
	running = true
	_refresh_state()
	_apply_wallet(payload.get("wallet", {}))
	print("[industrial] 已读取存档 %s（回合 %d）" % [SAVE_PATH, int(_state.get("turns", {}).get("used", 0))])
	return {"success": true, "message": "已读取存档", "error_code": "", "data": {"path": SAVE_PATH}}


## 只为打印用的命令条数（不做校验；解析失败就当 0）。
func _command_count(industrial_json: String) -> int:
	var json := JSON.new()
	if json.parse(industrial_json) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return 0
	var commands: Variant = (json.data as Dictionary).get("commands", [])
	return (commands as Array).size() if typeof(commands) == TYPE_ARRAY else 0


func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _wallet_snapshot() -> Dictionary:
	var wallet := get_node_or_null("/root/GameState")
	if wallet == null:
		return {"ore": 0, "materials": 0, "attack_level": 0}
	return {
		"ore": int(wallet.get("ore")),
		"materials": int(wallet.get("materials")),
		"attack_level": int(wallet.get("attack_level")),
	}


func _apply_wallet(data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	var wallet := get_node_or_null("/root/GameState")
	if wallet != null and wallet.has_method("apply_wallet"):
		wallet.apply_wallet(data)

func get_bridge() -> Node:
	return _bridge

## 一个逻辑刻等于多少墙钟秒（界面显示节奏用；判定不读它）。
func tick_seconds() -> float:
	return TICK_SECONDS

## 取出并广播自上次以来 Core 发出的表现层帧（记录栏的数据源，见 02 号文档 §9）。
func poll_events() -> Array:
	if _bridge == null:
		return []
	var envelope: Dictionary = _bridge.poll_events()
	if not bool(envelope.get("success", false)):
		error_occurred.emit(str(envelope.get("error_code", "")), str(envelope.get("message", "")))
		return []
	var data: Dictionary = envelope.get("data", {})
	var frames: Array = data.get("frames", [])
	events_arrived.emit(frames, int(data.get("dropped", 0)))
	return frames

# ----------------------------------------------------------------------
# 内部
# ----------------------------------------------------------------------

func _process(delta: float) -> void:
	# 只有玩家打开"自动推进"才让墙钟推着世界走；默认关，人工按「推进一回合」。
	if auto_advance:
		step_wall_time(delta)

func _apply_tick(count: int) -> bool:
	return bool(_tick_once().get("success", false))

func _tick_once() -> Dictionary:
	var envelope: Dictionary = _bridge.tick(1)
	if bool(envelope.get("success", false)):
		# 成功推进：立刻把帧流与状态快照都刷新一次，界面拿到的永远是"推完这一格之后"的事实。
		poll_events()
		_refresh_state()
		return envelope

	# 回合耗尽 / 结局已定：Core 会拒绝推进。这不是程序故障，是这一局走完了。
	running = false
	_refresh_state()
	run_stopped.emit(str(envelope.get("message", "回合已用尽")))
	error_occurred.emit(str(envelope.get("error_code", "")), str(envelope.get("message", "")))
	return envelope

func _refresh_state() -> void:
	var envelope: Dictionary = _bridge.get_state()
	if not bool(envelope.get("success", false)):
		error_occurred.emit(str(envelope.get("error_code", "")), str(envelope.get("message", "")))
		return
	_state = envelope.get("data", {})
	_collect_rewards()
	state_changed.emit(_state)
	var turns: Dictionary = _state.get("turns", {})
	turn_advanced.emit(int(turns.get("used", 0)), int(turns.get("limit", 0)))

## 转发一次写调用；成功才重拉快照。
func _write(method: String, args: Array) -> Dictionary:
	if _bridge == null:
		return _fail("not_initialized", "工业世界还没装配")
	var envelope: Dictionary = _bridge.callv(method, args)
	if bool(envelope.get("success", false)):
		_refresh_state()
	return envelope

## 扫一遍快照，把"这一局里第一次变成成功"的工单各发一次奖。
## 幂等靠 id 记账：重复刷新、界面反复重画都不会重复发。
func _collect_rewards() -> void:
	if _awarded_orders.is_empty() and _state.is_empty():
		return
	for entry in _state.get("orders", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("status", "")) != ORDER_STATUS_SUCCESS:
			continue
		var order_id := int(entry.get("id", -1))
		if order_id < 0 or _awarded_orders.has(order_id):
			continue
		_awarded_orders[order_id] = true
		_grant_materials(REWARD_PER_ORDER)
		reward_earned.emit(order_id, REWARD_PER_ORDER)

## 发材料：钱包在 GameState（autoload）。测试环境可能没有 autoload，此时只发信号不发账。
func _grant_materials(amount: int) -> void:
	var wallet := get_node_or_null("/root/GameState")
	if wallet != null and wallet.has_method("add_material"):
		wallet.add_material(amount)


func _fail(code: String, message: String) -> Dictionary:
	error_occurred.emit(code, message)
	return {"success": false, "message": message, "error_code": code}
