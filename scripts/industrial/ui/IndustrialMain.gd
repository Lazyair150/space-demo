extends Control
## 工业界面主控（阶段 6 产物）：`scenes/industrial/IndustrialMain.tscn` 的根脚本。
##
## 分工（与 03 号文档一致）：
## - **它不拥有世界状态**：每次操作后一律重拉快照，然后整块重画；界面只缓存"这一帧要怎么显示"。
## - **它不数时间**：回合由 `IndustrialRuntime` 的时间累积器或玩家点按决定，界面不参与。
## - **它不判断规则**：可行性、做法、进度、阻断原因全部原样取自 Core 的 DTO。
##
## 布局沿用 Web 版已被 6 个关卡验证过的两列结构（左生产、右工单），底部固定「推进一回合」。

const UiKit := preload("res://scripts/industrial/ui/UiKit.gd")
const BenchCardScene := preload("res://scripts/industrial/ui/BenchCard.gd")
const LinesPanelScene := preload("res://scripts/industrial/ui/LinesPanel.gd")
const WarehousePanelScene := preload("res://scripts/industrial/ui/WarehousePanel.gd")
const OrdersPanelScene := preload("res://scripts/industrial/ui/OrdersPanel.gd")
const LogPanelScene := preload("res://scripts/industrial/ui/LogPanel.gd")

const WORLD_PATH := "res://data/industrial/world_sandbox.json"
const TOAST_SECONDS := 3.0

var _runtime: Node
var _state: Dictionary = {}

# 顶栏
var _turns_label: Label
var _goal_label: Label
var _phase_label: Label
var _outcome_label: Label
var _busy_label: Label
var _ore_label: Label
var _material_label: Label
var _attack_label: Label
var _upgrade_attack_button: Button
var _save_button: Button
var _leave_button: Button
# 底栏
var _hint_label: Label
var _advance_button: Button
var _pause_button: Button
var _restart_button: Button
var _auto_check: CheckBox
# 面板
var _master_card: Node
var _slave_card: Node
var _lines_panel: Node
var _warehouse_panel: Node
var _orders_panel: Node
var _log_panel: Node
# 弹层
var _picker_layer: Control
var _picker_title: Label
var _picker_list: ItemList
var _picker_role := "master"
var _picker_mode := "workshop"
var _picker_names: Array[String] = []
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_timer: Timer
var _last_toast := ""
var _last_toast_at := 0

var _fault_label: Label
var _fault_retry: Button
var _restart_armed := false


func _ready() -> void:
	_build()
	_connect_runtime()


# ----------------------------------------------------------------------
# 构建界面
# ----------------------------------------------------------------------

func _build() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.color = UiKit.BG
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.name = "Root"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 12)
	add_child(margin)

	var column := UiKit.vbox(8)
	margin.add_child(column)

	column.add_child(_build_top_bar())

	var body := UiKit.hbox(10)
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var left := UiKit.vbox(8)
	left.name = "LeftColumn"
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.15
	body.add_child(left)

	_master_card = BenchCardScene.new()
	_master_card.name = "BenchCard_Master"
	_master_card.set_role("master")
	_master_card.picker_requested.connect(_on_picker_requested)
	left.add_child(_master_card)

	_slave_card = BenchCardScene.new()
	_slave_card.name = "BenchCard_Slave"
	_slave_card.set_role("slave")
	_slave_card.picker_requested.connect(_on_picker_requested)
	left.add_child(_slave_card)

	_lines_panel = LinesPanelScene.new()
	_lines_panel.name = "LinesPanel"
	_lines_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lines_panel.rate_requested.connect(_on_rate_requested)
	_lines_panel.liquid_rate_requested.connect(_on_liquid_rate_requested)
	_lines_panel.upgrade_requested.connect(_on_upgrade_requested)
	left.add_child(_lines_panel)

	_warehouse_panel = WarehousePanelScene.new()
	_warehouse_panel.name = "WarehousePanel"
	left.add_child(_warehouse_panel)

	var right := UiKit.vbox(8)
	right.name = "RightColumn"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)

	_orders_panel = OrdersPanelScene.new()
	_orders_panel.name = "OrdersPanel"
	_orders_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_orders_panel.action_requested.connect(_on_order_action)
	right.add_child(_orders_panel)

	_log_panel = LogPanelScene.new()
	_log_panel.name = "LogPanel"
	_log_panel.custom_minimum_size = Vector2(0, 190)
	right.add_child(_log_panel)

	column.add_child(_build_footer())
	_build_picker()
	_build_toast()
	_build_fault_notice()


func _build_top_bar() -> PanelContainer:
	var bar := UiKit.panel("TopBar")
	var row := UiKit.hbox(14)
	bar.add_child(row)
	_turns_label = UiKit.label("回合 0 / 0", UiKit.FONT_TITLE, UiKit.TEXT)
	row.add_child(_turns_label)
	_goal_label = UiKit.label("工单 0 / 0", UiKit.FONT_BODY, UiKit.TEXT)
	row.add_child(_goal_label)
	_phase_label = UiKit.label("准备", UiKit.FONT_BODY, UiKit.MUTED)
	row.add_child(_phase_label)
	_outcome_label = UiKit.label("", UiKit.FONT_BODY, UiKit.OK)
	row.add_child(_outcome_label)
	row.add_child(UiKit.spacer())
	_busy_label = UiKit.label("", UiKit.FONT_SMALL, UiKit.WARN)
	row.add_child(_busy_label)
	_ore_label = UiKit.label("矿石 0", UiKit.FONT_BODY, UiKit.ACCENT)
	_ore_label.tooltip_text = "战斗里打碎残骸得到的矿石，投入产线可以永久提高这一局的产能。"
	row.add_child(_ore_label)

	_material_label = UiKit.label("材料 0", UiKit.FONT_BODY, UiKit.OK)
	_material_label.tooltip_text = "工单结算成「成功」时发一张的强化材料。"
	row.add_child(_material_label)

	_attack_label = UiKit.label("攻击 Lv0", UiKit.FONT_BODY, UiKit.TEXT)
	_attack_label.tooltip_text = "每级 +1 点子弹伤害，战斗里的伤害就按这个算。"
	row.add_child(_attack_label)

	_upgrade_attack_button = UiKit.button("强化攻击", 96)
	_upgrade_attack_button.tooltip_text = "花 3 张强化材料，攻击力 +1（上限 5 级）。"
	_upgrade_attack_button.pressed.connect(_on_upgrade_attack_pressed)
	row.add_child(_upgrade_attack_button)
	_leave_button = UiKit.button("返回主菜单", 110)
	_leave_button.pressed.connect(_on_leave_pressed)
	row.add_child(_leave_button)
	return bar


func _build_footer() -> PanelContainer:
	var bar := UiKit.panel("FooterBar")
	var row := UiKit.hbox(10)
	bar.add_child(row)

	_hint_label = UiKit.wrap_label("", UiKit.FONT_SMALL, UiKit.MUTED)
	_hint_label.custom_minimum_size = Vector2(320, 0)
	row.add_child(_hint_label)

	_auto_check = CheckBox.new()
	_auto_check.text = "自动推进"
	_auto_check.button_pressed = false
	_auto_check.add_theme_font_size_override("font_size", UiKit.FONT_SMALL)
	_auto_check.toggled.connect(_on_auto_toggled)
	row.add_child(_auto_check)

	_pause_button = UiKit.button("暂停工业", 100)
	_pause_button.pressed.connect(_on_pause_pressed)
	row.add_child(_pause_button)

	_restart_button = UiKit.button("重开本关", 100)
	_restart_button.pressed.connect(_on_restart_pressed)
	row.add_child(_restart_button)

	_save_button = UiKit.button("保存进度", 100)
	_save_button.pressed.connect(_on_save_pressed)
	row.add_child(_save_button)

	row.add_child(UiKit.spacer())

	_advance_button = UiKit.button("推进一回合", 132)
	_advance_button.add_theme_font_size_override("font_size", UiKit.FONT_BODY)
	_advance_button.pressed.connect(_on_advance_pressed)
	row.add_child(_advance_button)
	return bar


func _build_picker() -> void:
	_picker_layer = Control.new()
	_picker_layer.name = "Picker_Workshop"
	_picker_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker_layer.visible = false
	add_child(_picker_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker_layer.add_child(center)

	var card := UiKit.panel("", UiKit.PANEL)
	card.custom_minimum_size = Vector2(560, 340)
	center.add_child(card)
	var box := UiKit.vbox(8)
	card.add_child(box)

	_picker_title = UiKit.title("选择装配台")
	box.add_child(_picker_title)

	_picker_list = ItemList.new()
	_picker_list.custom_minimum_size = Vector2(0, 220)
	_picker_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_picker_list.add_theme_font_size_override("font_size", UiKit.FONT_SMALL)
	box.add_child(_picker_list)

	var actions := UiKit.hbox(8)
	actions.add_child(UiKit.spacer())
	var cancel := UiKit.button("取消", 88)
	cancel.pressed.connect(func() -> void: _picker_layer.hide())
	actions.add_child(cancel)
	var confirm := UiKit.button("确定", 88)
	confirm.pressed.connect(_on_picker_confirm)
	actions.add_child(confirm)
	box.add_child(actions)


func _build_toast() -> void:
	_toast_panel = PanelContainer.new()
	_toast_panel.name = "Toast"
	_toast_panel.add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.PANEL_SOFT))
	_toast_panel.anchor_left = 0.5
	_toast_panel.anchor_right = 0.5
	_toast_panel.anchor_top = 1.0
	_toast_panel.anchor_bottom = 1.0
	_toast_panel.offset_left = -280
	_toast_panel.offset_right = 280
	_toast_panel.offset_top = -104
	_toast_panel.offset_bottom = -62
	_toast_panel.visible = false
	add_child(_toast_panel)

	_toast_label = UiKit.wrap_label("", UiKit.FONT_SMALL, UiKit.TEXT)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_panel.add_child(_toast_label)

	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = TOAST_SECONDS
	_toast_timer.timeout.connect(func() -> void: _toast_panel.hide())
	add_child(_toast_timer)


func _build_fault_notice() -> void:
	_fault_label = UiKit.wrap_label("", UiKit.FONT_BODY, UiKit.BAD)
	_fault_label.visible = false
	_fault_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_fault_label.custom_minimum_size = Vector2(760, 0)
	_fault_label.offset_top = 120
	add_child(_fault_label)

	_fault_retry = UiKit.button("重试", 96)
	_fault_retry.visible = false
	_fault_retry.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_fault_retry.offset_top = 180
	_fault_retry.pressed.connect(_connect_runtime)
	add_child(_fault_retry)


# ----------------------------------------------------------------------
# 与运行时连线
# ----------------------------------------------------------------------

func _connect_runtime() -> void:
	# 矿石可能在本界面打开期间变化（例如自动推进时后台仍在跑），拿不到就算了：它不是必需依赖
	var wallet := get_node_or_null("/root/GameState")
	if wallet != null and wallet.has_signal("ore_changed") and not wallet.ore_changed.is_connected(_on_ore_changed):
		wallet.ore_changed.connect(_on_ore_changed)

	_runtime = get_node_or_null("/root/IndustrialRuntime")
	if _runtime == null:
		_enter_fault("工业运行时没装配（检查 project.godot 的 [autoload] 段）。")
		return

	if not _runtime.state_changed.is_connected(_on_state_changed):
		_runtime.state_changed.connect(_on_state_changed)
		_runtime.events_arrived.connect(_on_events_arrived)
		if _runtime.has_signal("reward_earned"):
			_runtime.reward_earned.connect(_on_reward_earned)
		_runtime.error_occurred.connect(_on_error_occurred)
		_runtime.run_stopped.connect(_on_run_stopped)
		_runtime.ticks_dropped.connect(_on_ticks_dropped)

	var started: Dictionary = _runtime.ensure_started(WORLD_PATH, -1)
	if not bool(started.get("success", false)):
		_enter_fault("工业世界装配失败：%s" % str(started.get("message", "未知原因")))
		return

	_exit_fault()
	_apply_state(_runtime.get_state())


func _enter_fault(message: String) -> void:
	_fault_label.text = message
	_fault_label.show()
	_fault_retry.show()
	_hint_label.text = "工业系统没起来，界面上的数字都不可信。"


func _exit_fault() -> void:
	_fault_label.hide()
	_fault_retry.hide()


# ----------------------------------------------------------------------
# 重画
# ----------------------------------------------------------------------

func _apply_state(state: Dictionary) -> void:
	_state = state

	var turns: Dictionary = state.get("turns", {})
	var used := int(turns.get("used", 0))
	var limit := int(turns.get("limit", 0))
	var exhausted := bool(turns.get("exhausted", false))
	_turns_label.text = "回合 %d / %s" % [used, "不限" if limit <= 0 else str(limit)]
	_turns_label.add_theme_color_override("font_color", UiKit.WARN if exhausted else UiKit.TEXT)

	var level: Dictionary = state.get("level", {})
	var goal_orders := int(level.get("goalOrders", 0))
	var completed := int(level.get("completedOrders", 0))
	_goal_label.text = "工单 %d / %d" % [completed, goal_orders] if goal_orders > 0 else "沙盒模式"
	_goal_label.add_theme_color_override("font_color", UiKit.OK if goal_orders > 0 and completed >= goal_orders else UiKit.TEXT)

	var phase := str(state.get("phase", ""))
	_phase_label.text = _phase_text(phase)

	var outcome := str(level.get("outcome", "inProgress"))
	if outcome == "inProgress":
		_outcome_label.hide()
	else:
		_outcome_label.show()
		_outcome_label.text = "达成 · %s" % str(level.get("reason", "")) if outcome == "won" else "失败 · %s" % str(level.get("reason", ""))
		_outcome_label.add_theme_color_override("font_color", UiKit.OK if outcome == "won" else UiKit.BAD)

	# 执行中的过程数（顶栏"忙不忙"的唯一来源）
	var running_processes := 0
	for process in state.get("processes", []):
		if str(process.get("kind", "")) == "order_execution" and str(process.get("state", "")) == "running":
			running_processes += 1
	_busy_label.text = "执行中 %d" % running_processes if running_processes > 0 else ""
	if running_processes > 0:
		_busy_label.tooltip_text = "工单执行中：换台、档位、投矿、派单都已锁定；要改就等它结算或先取消。"

	# 执行中锁定：过程在跑时改配置会让"这一步用的是哪台"失去定义（见 08 号文档 §3）
	var locked := _has_active_process(state)
	_master_card.set_locked(locked)
	_slave_card.set_locked(locked)
	_lines_panel.set_locked(locked)
	_orders_panel.set_locked(locked)

	# 装配台
	var workshops: Array = state.get("workshops", [])
	var global_state: Dictionary = state.get("globalState", {})
	var master_index := _int_or(global_state.get("currentMaster", null), -1)
	var slave_index := _int_or(global_state.get("currentSlave", null), -1)
	_master_card.bind(_workshop_at(workshops, master_index))
	_slave_card.bind(_workshop_at(workshops, slave_index))

	_lines_panel.bind(state.get("producerStatus", {}), _ore_value())
	_ore_label.text = "矿石 %d" % _ore_value()
	_warehouse_panel.bind(state.get("warehouse", {}))

	var processes: Array = state.get("processes", [])
	_orders_panel.bind(state.get("orders", []), processes, phase, state)

	# 底栏
	var ended := exhausted or outcome != "inProgress"
	_advance_button.disabled = ended
	_pause_button.text = "继续工业" if _runtime.user_paused else "暂停工业"
	_pause_button.disabled = ended
	_auto_check.set_pressed_no_signal(bool(_runtime.auto_advance))
	_hint_label.text = _hint_text(ended, exhausted, outcome, level, state)


func _hint_text(ended: bool, exhausted: bool, outcome: String, level: Dictionary, state: Dictionary) -> String:
	if exhausted:
		return "本关回合已用完（%d / %d），不能再推进。" % [int(state.get("turns", {}).get("used", 0)), int(state.get("turns", {}).get("limit", 0))]
	if outcome != "inProgress":
		return "本关已结束：%s" % str(level.get("reason", ""))
	if _runtime.user_paused:
		return "工业已暂停：推进按钮暂时不生效，回合数不会动。"
	if state.get("orders", []).is_empty():
		return "还没有工单。派一张随机单，或重开本关。"
	if int(state.get("turns", {}).get("used", 0)) == 0:
		return "先点「推进一回合」看看这一格会发生什么；订单要能开始，得先判定可行。"
	return "推进一回合：产线出货 → 仓库 → 主装配台，工单按步推进。"


func _phase_text(phase: String) -> String:
	match phase:
		"setup":
			return "准备阶段"
		"running":
			return "执行中"
		"settled":
			return "已结算"
		_:
			return phase


## `int()` 遇到 null 会报 "Nonexistent 'int' constructor"；契约里 currentMaster/currentSlave
## 是可空整数（没设主台就是 null），所以统一走这个入口。
## 是否有"在册"的工单过程。
## 注意 created/ready 也算：`startOrder` 刚返回时过程还没跑到 running，
## 若此时允许改配置，第一步就会用到与报价不符的工作台。
func _has_active_process(state: Dictionary) -> bool:
	for process in state.get("processes", []):
		if str(process.get("kind", "")) != "order_execution":
			continue
		var process_state := str(process.get("state", ""))
		if process_state == "succeeded" or process_state == "failed" or process_state == "aborted":
			continue
		return true
	return false


func _int_or(value: Variant, fallback: int) -> int:
	return int(value) if value != null else fallback


func _workshop_at(workshops: Array, index: int) -> Dictionary:
	for workshop in workshops:
		if int(workshop.get("index", -1)) == index:
			return workshop
	return {}


# ----------------------------------------------------------------------
# 信号
# ----------------------------------------------------------------------

func _on_state_changed(state: Dictionary) -> void:
	_apply_state(state)


func _on_events_arrived(frames: Array, dropped: int) -> void:
	_log_panel.append_frames(frames, dropped)


func _on_error_occurred(code: String, message: String) -> void:
	_toast(false, message if message != "" else code)


func _on_run_stopped(reason: String) -> void:
	if reason == "stopped":
		return
	_toast(true, "工业停下了：%s" % reason)


func _on_ticks_dropped(count: int) -> void:
	_toast(true, "卡顿后丢弃了 %d 个逻辑刻（不补算）。" % count)


# ----------------------------------------------------------------------
# 动作
# ----------------------------------------------------------------------

func _on_advance_pressed() -> void:
	if _runtime == null or _advance_button.disabled:
		return
	var envelope: Dictionary = _runtime.advance_manual()
	if not bool(envelope.get("success", false)):
		_toast(false, str(envelope.get("message", "推进失败")))
		return
	# 推完之后重新判定可行性：世界变了，上一帧的"可行"可能已经不作数
	_runtime.check_all_feasibility()


func _on_pause_pressed() -> void:
	if _runtime == null:
		return
	_runtime.set_user_paused(not _runtime.user_paused)
	_apply_state(_runtime.get_state())


func _on_auto_toggled(value: bool) -> void:
	if _runtime == null:
		return
	_runtime.auto_advance = value
	if value:
		_toast(true, "自动推进已开：每 %.1f 秒走一回合。" % _runtime.tick_seconds())
	else:
		_toast(true, "自动推进已关。")


func _on_restart_pressed() -> void:
	if _runtime == null:
		return
	if not _restart_armed:
		_restart_armed = true
		_restart_button.text = "再点一次确认"
		await get_tree().create_timer(3.0).timeout
		_restart_armed = false
		_restart_button.text = "重开本关"
		return
	_restart_armed = false
	_restart_button.text = "重开本关"
	var envelope: Dictionary = _runtime.reset_world()
	if not bool(envelope.get("success", false)):
		_toast(false, str(envelope.get("message", "重开失败")))
		return
	_log_panel.clear()
	_toast(true, "本关已重开（世界回到开局）。")


func _on_rate_requested(producer_name: String, shape: String, rate: float) -> void:
	if _runtime == null:
		return
	var envelope: Dictionary = _runtime.update_producer_rate(producer_name, shape, rate)
	if not bool(envelope.get("success", false)):
		_toast(false, str(envelope.get("message", "改速率失败")))


## 材料/攻击力那一排：数值 + 按钮可用性（材料不够或已到顶就灰掉，别让玩家点了才知道）。
func _refresh_reward_bar() -> void:
	var wallet := get_node_or_null("/root/GameState")
	if _material_label != null:
		_material_label.text = "材料 %d" % _material_value()
	if _attack_label != null:
		_attack_label.text = "攻击 Lv%d" % _attack_level()
	if _upgrade_attack_button == null:
		return
	var can_upgrade := false
	if wallet != null and wallet.has_method("upgrade_attack"):
		can_upgrade = _attack_level() < int(wallet.get("MAX_ATTACK_LEVEL")) and _material_value() >= int(wallet.get("ATTACK_COST"))
	_upgrade_attack_button.disabled = not can_upgrade
	if _attack_level() >= (int(wallet.get("MAX_ATTACK_LEVEL")) if wallet != null else 5):
		_upgrade_attack_button.text = "已到顶"
	else:
		_upgrade_attack_button.text = "强化攻击（材料 %d）" % (int(wallet.get("ATTACK_COST")) if wallet != null else 3)


func _material_value() -> int:
	var wallet := get_node_or_null("/root/GameState")
	return int(wallet.get("materials")) if wallet != null else 0


func _attack_level() -> int:
	var wallet := get_node_or_null("/root/GameState")
	return int(wallet.get("attack_level")) if wallet != null else 0


func _on_upgrade_attack_pressed() -> void:
	var wallet := get_node_or_null("/root/GameState")
	if wallet == null:
		_toast(true, "没有玩家钱包，无法强化")
		return
	if not wallet.upgrade_attack():
		_toast(true, "材料不够，或攻击力已经到顶")
		return
	_refresh_reward_bar()
	_toast(false, "攻击力升到 Lv%d（子弹伤害 %d）" % [_attack_level(), int(wallet.attack_damage())])


func _on_reward_earned(order_id: int, amount: int) -> void:
	_refresh_reward_bar()
	_toast(false, "工单 #%d 结算：+%d 强化材料" % [order_id, amount])


func _on_ore_changed(_amount: int) -> void:
	if _ore_label != null:
		_ore_label.text = "矿石 %d" % _ore_value()
	_refresh_reward_bar()
	if not _state.is_empty():
		_apply_state(_state)


## 投矿提档：矿石在 GameState 里（跨场景存活），扣矿成功才动世界。
## 先扣矿、失败退回 —— 不制造"界面扣了矿但世界没变"的中间态。
func _on_upgrade_requested(producer_name: String, shape: String, target: float, cost: int) -> void:
	if not _spend_ore(cost):
		_toast(true, "矿石不够：需要 %d，现有 %d" % [cost, _ore_value()])
		_apply_state(_state)
		return
	var envelope: Dictionary = _runtime.update_producer_rate(producer_name, shape, target)
	if not bool(envelope.get("success", false)):
		_add_ore(cost)
		_toast(false, "提速失败：%s" % str(envelope.get("message", "")))
		_apply_state(_state)
		return
	_toast(true, "%s 的 %s 提到 %s" % [producer_name, shape, UiKit.rate_text(target)])
	_apply_state(_state)


## 矿石存在 GameState（autoload）里：跨战斗、跨场景累积。
## 这里用 `/root/GameState` 动态取，而不是写死 `GameState.xxx` —— 在 `--script` 测试环境里
## autoload 不装载，写死标识符会让整个脚本编译失败。
func _ore_value() -> int:
	var state := get_node_or_null("/root/GameState")
	return int(state.ore) if state != null else 0


func _spend_ore(cost: int) -> bool:
	var state := get_node_or_null("/root/GameState")
	if state == null or not state.has_method("spend_ore"):
		return false
	return bool(state.spend_ore(cost))


func _add_ore(amount: int) -> void:
	var state := get_node_or_null("/root/GameState")
	if state != null and state.has_method("add_ore"):
		state.add_ore(amount)


## 回主菜单：只切场景。工业世界留在 autoload 的运行时里，回来还是这一局。
func _on_leave_pressed() -> void:
	# 离开工业舱前先落盘：返回菜单之后这一局还在，别让玩家以为切一下就丢了。
	if _runtime != null and _runtime.has_method("save_game"):
		_runtime.save_game()
	get_tree().change_scene_to_file("res://scenes/menus/MainMenu.tscn")


func _on_save_pressed() -> void:
	if _runtime == null or not _runtime.has_method("save_game"):
		_toast(true, "工业运行时没装配，存不了档")
		return
	var result: Dictionary = _runtime.save_game()
	if bool(result.get("success", false)):
		_toast(false, "进度已保存（再次进入工业舱会接着这一局）")
	else:
		_toast(true, str(result.get("message", "保存失败")))


func _on_liquid_rate_requested(liquid: String, rate: float) -> void:
	if _runtime == null:
		return
	var envelope: Dictionary = _runtime.update_liquid_rate(liquid, rate)
	if not bool(envelope.get("success", false)):
		_toast(false, str(envelope.get("message", "改工质速率失败")))


func _on_order_action(kind: String, payload: Dictionary) -> void:
	if _runtime == null:
		return
	match kind:
		"random":
			var created: Dictionary = _runtime.create_random_order()
			if not bool(created.get("success", false)):
				_toast(false, str(created.get("message", "派单失败")))
				return
			_runtime.check_all_feasibility()
		"templates":
			_open_template_picker()
		"check_all":
			var checked: Dictionary = _runtime.check_all_feasibility()
			if not bool(checked.get("success", false)):
				_toast(false, str(checked.get("message", "检查失败")))
		"start":
			var started: Dictionary = _runtime.start_order(int(payload.get("index", 0)))
			if not bool(started.get("success", false)):
				_toast(false, str(started.get("message", "开始失败")))
			else:
				_toast(true, "工单已开始：之后每推进一回合走一段。")
				_runtime.check_all_feasibility()
		"delete":
			var deleted: Dictionary = _runtime.delete_order(int(payload.get("index", 0)))
			if not bool(deleted.get("success", false)):
				_toast(false, str(deleted.get("message", "删除失败")))
		"cancel":
			var cancelled: Dictionary = _runtime.cancel_process(int(payload.get("process_id", 0)))
			if not bool(cancelled.get("success", false)):
				_toast(false, str(cancelled.get("message", "取消失败")))
			else:
				_toast(true, "已取消：已经投入的舱段与工质不会退回（内核语义）。")
		_:
			push_warning("未知的工单动作：%s" % kind)


func _on_picker_requested(role: String) -> void:
	if _runtime == null:
		return
	if role == "slave" and not _slave_card.is_empty_workshop():
		# 副台已选：这个按钮是"撤掉副台"
		var dropped: Dictionary = _runtime.set_slave(-1)
		if not bool(dropped.get("success", false)):
			_toast(false, str(dropped.get("message", "撤掉副台失败")))
		return

	_picker_role = role
	_picker_mode = "workshop"
	_picker_names.clear()
	_picker_title.text = "选择主装配台" if role == "master" else "选择副装配台"
	_picker_list.clear()

	var workshops: Array = _state.get("workshops", [])
	if workshops.is_empty():
		_toast(false, "这个世界里没有可选装配台。")
		return

	for workshop in workshops:
		var base: Array = workshop.get("baseMarks", [])
		var extra: Array = workshop.get("additionalMarks", [])
		var ban: Array = workshop.get("ban", [])
		var text := "%s　［基础 %s｜附加 %s｜禁 %s］" % [
			str(workshop.get("name", "")),
			_join(base),
			_join(extra) if not extra.is_empty() else "无",
			_join(ban) if not ban.is_empty() else "无",
		]
		_picker_list.add_item(text)
	_picker_layer.show()


func _on_picker_confirm() -> void:
	var selected := _picker_list.get_selected_items()
	if selected.is_empty():
		_toast(false, "先选一项。")
		return
	var index := int(selected[0])
	if _picker_mode == "template":
		_confirm_template(index)
		return
	var envelope: Dictionary
	if _picker_role == "master":
		envelope = _runtime.set_master(index)
	else:
		envelope = _runtime.set_slave(index)
	if not bool(envelope.get("success", false)):
		_toast(false, str(envelope.get("message", "切换失败")))
		return
	_picker_layer.hide()


func _join(items: Array) -> String:
	var parts: Array[String] = []
	for item in items:
		parts.append(str(item))
	return "、".join(parts)


# ----------------------------------------------------------------------
# Toast
# ----------------------------------------------------------------------

func _toast(is_info: bool, message: String) -> void:
	if message.strip_edges() == "":
		return
	# 同一条消息 0.5 秒内只弹一次：失败时 Bridge 与运行时可能各报一次同一条错误
	var now := Time.get_ticks_msec()
	if message == _last_toast and now - _last_toast_at < 500:
		return
	_last_toast = message
	_last_toast_at = now
	_toast_label.text = message
	_toast_label.add_theme_color_override("font_color", UiKit.TEXT if is_info else UiKit.BAD)
	_toast_panel.show()
	_toast_timer.start()

func _open_template_picker() -> void:
	if _runtime == null:
		return
	var envelope: Dictionary = _runtime.get_order_templates()
	if not bool(envelope.get("success", false)):
		_toast(false, str(envelope.get("message", "读取模板失败")))
		return

	var data = envelope.get("data")
	var templates: Array = data.get("templates", []) if data is Dictionary else []
	if templates.is_empty():
		_toast(false, "这个世界没有配置工单模板，只能用「随机派一单」。")
		return

	_picker_mode = "template"
	_picker_names.clear()
	_picker_title.text = "按模板派工单"
	_picker_list.clear()
	for template in templates:
		var parts: Array[String] = []
		for requirement in template.get("requirements", []):
			var shape := str(requirement.get("shape", ""))
			var liquid = requirement.get("liquid")
			parts.append(shape if liquid == null else "%s + %s" % [shape, str(liquid)])
		_picker_names.append(str(template.get("name", "")))
		_picker_list.add_item("%s　［%s · %s］" % [
			str(template.get("name", "")),
			str(template.get("type", "")),
			" / ".join(parts),
		])
	_picker_layer.show()


func _confirm_template(index: int) -> void:
	var template_name := _picker_names[index] if index < _picker_names.size() else ""
	var created: Dictionary = _runtime.create_order_from_template(template_name)
	if not bool(created.get("success", false)):
		_toast(false, str(created.get("message", "派单失败")))
		return
	_picker_layer.hide()
	_runtime.check_all_feasibility()
	_toast(true, "已派工单：%s" % template_name)
