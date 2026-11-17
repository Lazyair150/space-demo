extends PanelContainer
## 工单面板（原 `play.html` 的订单面板）。
##
## 界面在这里的职责只有"如实展示 + 转发点击"：
## - 能不能做由 Core 的可行性分析回答（`feasible` / `blockage` / `reason` 原样显示）；
## - 怎么做由 Core 的求解路径回答（`solverPath` 的 operation 原文，界面不翻译、不推断）；
## - 做完需要几刻由 Core 的过程快照回答（`currentStep` / `totalSteps` / `ticksUntilNextUnit`）。
##
## 硬规则（03 号文档 §0 #2）：**先看见做法，再决定做** —— 所以"做法"必须在点「开始」之前可见。

signal action_requested(kind: String, payload: Dictionary)

const UiKit := preload("res://scripts/industrial/ui/UiKit.gd")

const STATUS_COLORS := {
	"待执行": UiKit.MUTED,
	"执行中": UiKit.ACCENT,
	"成功": UiKit.OK,
	"失败": UiKit.BAD,
}

var _built := false
var _empty_hint: Label
var _cards: VBoxContainer


func _ready() -> void:
	if _built:
		return
	_built = true
	var box := UiKit.vbox(6)
	add_child(box)

	var head := UiKit.hbox(8)
	head.add_child(UiKit.title("工单"))
	head.add_child(UiKit.spacer())
	var pick_template := UiKit.small_button("选模板", 72)
	pick_template.pressed.connect(func() -> void: action_requested.emit("templates", {}))
	head.add_child(pick_template)
	var check_all := UiKit.small_button("检查全部", 84)
	check_all.pressed.connect(func() -> void: action_requested.emit("check_all", {}))
	head.add_child(check_all)
	var random_order := UiKit.small_button("随机派一单", 96)
	random_order.pressed.connect(func() -> void: action_requested.emit("random", {}))
	head.add_child(random_order)
	box.add_child(head)

	_empty_hint = UiKit.wrap_label("", UiKit.FONT_SMALL, UiKit.MUTED)
	box.add_child(_empty_hint)

	_cards = UiKit.vbox(8)
	box.add_child(UiKit.scroll(_cards, 220))


func bind(orders: Array, processes: Array, phase: String) -> void:
	if not _built:
		_ready()

	UiKit.clear_children(_cards)

	if orders.is_empty():
		_empty_hint.text = "还没有工单。派一张随机单，或重开本关。"
		_empty_hint.show()
		return
	_empty_hint.hide()

	for order in orders:
		var card := _order_card(order, _process_for(processes, _int_or(order.get("id", -1), -1)), phase)
		if card != null:
			_cards.add_child(card)


func _process_for(processes: Array, order_id: int) -> Dictionary:
	for process in processes:
		if str(process.get("kind", "")) != "order_execution":
			continue
		if _int_or(process.get("subjectId", null), -2) != order_id:
			continue
		var state := str(process.get("state", ""))
		if state == "running" or state == "blocked" or state == "ready" or state == "created":
			return process
	return {}


func _order_card(order: Dictionary, process: Dictionary, phase: String) -> PanelContainer:
	var card := UiKit.panel("", UiKit.PANEL_SOFT)
	var box := UiKit.vbox(6)
	card.add_child(box)

	var order_id := int(order.get("id", 0))
	var order_type := str(order.get("type", ""))
	var status := str(order.get("status", ""))
	var feasibility: Dictionary = order.get("feasibilityResult", {}) if order.get("feasibilityResult", null) != null else {}

	# 标题行：类型 · 名称 · 状态
	var head := UiKit.hbox(8)
	head.add_child(UiKit.label("%s · %s" % [order_type, _order_name(order)], UiKit.FONT_BODY, UiKit.TEXT))
	head.add_child(UiKit.spacer())
	var status_color: Color = STATUS_COLORS.get(status, UiKit.MUTED)
	head.add_child(UiKit.label(status if status != "" else "未知", UiKit.FONT_SMALL, status_color))
	box.add_child(head)

	# 需求行
	var requirements: Array = order.get("requirements", [])
	var requirement_parts: Array[String] = []
	for requirement in requirements:
		var shape := str(requirement.get("shape", ""))
		var liquid = requirement.get("liquid", null)
		requirement_parts.append("%s（%s）" % [shape, "空舱" if liquid == null else "装 %s" % str(liquid)])
	box.add_child(UiKit.wrap_label("需求：%s" % "、".join(requirement_parts), UiKit.FONT_SMALL, UiKit.TEXT))

	# 已经结束的单：可行性、做法、开始按钮都没有意义了，只留一句结果和"清掉它"。
	if status == "成功" or status == "失败":
		box.add_child(UiKit.label("这一单已结束（%s），不再更新可行性。" % status, UiKit.FONT_SMALL, UiKit.MUTED))
		var settle_actions := UiKit.hbox(6)
		settle_actions.add_child(UiKit.spacer())
		var settle_remove := UiKit.small_button("删除", 64)
		settle_remove.pressed.connect(func() -> void:
			action_requested.emit("delete", {"index": int(order.get("index", 0)), "id": order_id}))
		settle_actions.add_child(settle_remove)
		box.add_child(settle_actions)
		return card

	# 可行性
	var feasible := bool(feasibility.get("feasible", false))
	var checked := not feasibility.is_empty()
	var direct := float(feasibility.get("directCount", 0.0))
	var total := maxf(float(requirements.size()), 1.0)
	if checked:
		var bar := ProgressBar.new()
		bar.max_value = total
		bar.value = minf(direct, total)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 6)
		box.add_child(bar)
		box.add_child(UiKit.label("现在就能直接用上的：%s / %d 件" % [UiKit.rate_text(direct), requirements.size()],
			UiKit.FONT_SMALL, UiKit.OK if feasible else UiKit.WARN))
		if not feasible:
			var reason := _text(feasibility.get("reason"))
			if reason.is_empty():
				reason = _text(feasibility.get("blockage"))
			box.add_child(UiKit.wrap_label("不可行：%s" % (reason if reason != "" else "内核没有给出原因"),
				UiKit.FONT_SMALL, UiKit.WARN))
	else:
		box.add_child(UiKit.label("可行性：待检查（点「检查全部」）", UiKit.FONT_SMALL, UiKit.MUTED))

	# 做法：先看见再决定做
	var steps := _path_steps(feasibility)
	if not steps.is_empty():
		var lines: Array[String] = []
		for index in range(mini(steps.size(), 6)):
			lines.append("　%d. %s" % [index + 1, steps[index]])
		if steps.size() > 6:
			lines.append("　… 共 %d 步" % steps.size())
		box.add_child(UiKit.wrap_label("做法：\n%s" % "\n".join(lines), UiKit.FONT_SMALL, UiKit.MUTED))

	# 过程进度：刻数来自 Core，不是界面自己算的时间
	if not process.is_empty():
		var current := _int_or(process.get("currentStep", 0), 0)
		var total_steps := _int_or(process.get("totalSteps", 0), 0)
		var next_unit := _int_or(process.get("ticksUntilNextUnit", 0), 0)
		var remaining := _int_or(process.get("remainingTicks", 0), 0)
		var progress_text := "执行中：第 %d / %d 步　·　距下一单位 %d 刻　·　共需 %d 刻" % [
			current, total_steps, next_unit, remaining
		]
		box.add_child(UiKit.wrap_label(progress_text, UiKit.FONT_SMALL, UiKit.ACCENT))
		var blocked := str(process.get("blockedReason", ""))
		if blocked != "":
			box.add_child(UiKit.wrap_label("卡住了：%s" % blocked, UiKit.FONT_SMALL, UiKit.WARN))

	# 动作行
	var actions := UiKit.hbox(6)
	actions.add_child(UiKit.spacer())

	var running := not process.is_empty()
	if running:
		var cancel := UiKit.small_button("取消", 64)
		cancel.pressed.connect(func() -> void:
			action_requested.emit("cancel", {"process_id": int(process.get("id", 0))}))
		actions.add_child(cancel)
	else:
		var start := UiKit.small_button("开始", 64)
		# 只有"待执行 + 准备阶段 + 已判定可行"才点亮；其余情况保持灰掉并说明原因在下方
		start.disabled = not (status == "待执行" and phase == "setup" and feasible)
		start.pressed.connect(func() -> void:
			action_requested.emit("start", {"index": int(order.get("index", 0)), "id": order_id}))
		actions.add_child(start)

		var remove := UiKit.small_button("删除", 64)
		remove.disabled = status != "待执行"
		remove.pressed.connect(func() -> void:
			action_requested.emit("delete", {"index": int(order.get("index", 0)), "id": order_id}))
		actions.add_child(remove)

	box.add_child(actions)

	# 为什么不能点「开始」——把原因写出来，别让按钮自己沉默
	if status == "待执行" and not feasible:
		var why := "这一单现在做不了（见上面的不可行原因）。"
		if checked and not _text(feasibility.get("reason")).is_empty():
			why = "这一单现在做不了：%s" % _text(feasibility.get("reason"))
		box.add_child(UiKit.wrap_label(why, UiKit.FONT_SMALL, UiKit.MUTED))
	elif status == "待执行" and phase != "setup":
		box.add_child(UiKit.wrap_label("当前处于「%s」阶段，只有准备阶段才能开始新工单。" % phase,
			UiKit.FONT_SMALL, UiKit.MUTED))

	return card


func _order_name(order: Dictionary) -> String:
	var description := str(order.get("description", ""))
	if description != "":
		return description
	return "工单 #%d" % int(order.get("id", 0))


## 求解路径的「人读操作」原文；主从分工（B 类）用一段前缀说明，不做推断。
## 契约里这些字段可能是 null。GDScript 的 `str(null)` 会得到字面串 "<null>"，
## 直接拼进文案就会把"内核没给原因"显示成 `不可行：<null>` —— 一律先过这里。
func _text(value: Variant) -> String:
	return "" if value == null else str(value)


## 注意：`solverPath` / `masterPath` 在不可行或未检查时是 null，不能直接当 Array 用。
func _path_steps(feasibility: Dictionary) -> Array[String]:
	var steps: Array[String] = []
	var master_path = feasibility.get("masterPath", null)
	if master_path is Array and not (master_path as Array).is_empty():
		steps.append("先把主装配台改成可迁移状态（%d 步）" % (master_path as Array).size())
	var solver_path = feasibility.get("solverPath", null)
	if solver_path is Array:
		for step in solver_path:
			var operation := str(step.get("operation", ""))
			if operation == "":
				operation = str(step.get("type", ""))
			steps.append(operation)
	return steps


## DTO 里的可空整数（例如过程中的 `remainingTicks`）不能直接喂给 `int()`：
## `int(null)` 会报 "Nonexistent 'int' constructor" 并打断整块重画。
func _int_or(value: Variant, fallback: int) -> int:
	return int(value) if value != null else fallback
