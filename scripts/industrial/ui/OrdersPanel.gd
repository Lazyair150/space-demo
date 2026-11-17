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

## 过程在跑时，界面进入"只读"：派单/检查按钮禁用，配置类按钮由 IndustrialMain 一并锁。
var _locked := false
var _state: Dictionary = {}
var _pick_template: Button
var _check_all: Button
var _random_order: Button

## 每单位推进需要的刻数：唯一来源在 IndustrialPacing.gd（经验值，非 Core 契约）。
const Pacing := preload("res://scripts/industrial/IndustrialPacing.gd")

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
	_pick_template = UiKit.small_button("选模板", 72)
	_pick_template.pressed.connect(func() -> void: action_requested.emit("templates", {}))
	head.add_child(_pick_template)
	_check_all = UiKit.small_button("检查全部", 84)
	_check_all.pressed.connect(func() -> void: action_requested.emit("check_all", {}))
	head.add_child(_check_all)
	_random_order = UiKit.small_button("随机派一单", 96)
	_random_order.pressed.connect(func() -> void: action_requested.emit("random", {}))
	head.add_child(_random_order)
	box.add_child(head)

	_empty_hint = UiKit.wrap_label("", UiKit.FONT_SMALL, UiKit.MUTED)
	box.add_child(_empty_hint)

	_cards = UiKit.vbox(8)
	box.add_child(UiKit.scroll(_cards, 220))


func set_locked(locked: bool) -> void:
	_locked = locked
	if _pick_template != null:
		_pick_template.disabled = locked
	if _check_all != null:
		_check_all.disabled = locked
	if _random_order != null:
		_random_order.disabled = locked


## `state` 只用于第二层"检查清单"（仓库/主从台/禁令），不参与可行性判断。
func bind(orders: Array, processes: Array, phase: String, state: Dictionary = {}) -> void:
	if not _built:
		_ready()
	_state = state

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

	# 报价：先看见再做决定。
	# 事实（来自 Core）：做法原文、消耗、是否要先迁移、求解器是否给出确定结论。
	# 估算（界面算的）：预计刻数 = 计时步数 × TICKS_PER_UNIT，明确标「估算」，不当契约。
	var steps := _path_steps(feasibility)
	if not steps.is_empty():
		var lines: Array[String] = []
		for index in range(mini(steps.size(), 6)):
			lines.append("　%d. %s" % [index + 1, steps[index]])
		if steps.size() > 6:
			lines.append("　… 共 %d 步" % steps.size())
		box.add_child(UiKit.wrap_label("做法：\n%s" % "\n".join(lines), UiKit.FONT_SMALL, UiKit.MUTED))

	if checked and feasible:
		var timed := _timed_steps(feasibility)
		var untimed := _untimed_steps(feasibility)
		var quote := UiKit.label("报价：计时 %d 步 · 不计时 %d 步 · 估算约 %d 刻" % [
			timed, untimed, timed * Pacing.TICKS_PER_UNIT], UiKit.FONT_SMALL, UiKit.TEXT)
		quote.tooltip_text = Pacing.PACING_NOTE
		box.add_child(quote)

		var cost := _cost_summary(feasibility)
		if cost != "":
			box.add_child(UiKit.wrap_label("消耗：%s" % cost, UiKit.FONT_SMALL, UiKit.TEXT))

		var risks := _risks(feasibility)
		for risk in risks:
			box.add_child(UiKit.wrap_label("注意：%s" % risk, UiKit.FONT_SMALL, UiKit.WARN))
	elif checked and not feasible:
		for tip in _checklist(feasibility, order):
			box.add_child(UiKit.wrap_label("检查：%s" % tip, UiKit.FONT_SMALL, UiKit.MUTED))

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
		var start := UiKit.small_button("按此方案执行", 116)
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


## 计时步 = 除 MATCH 以外的步骤；MATCH 是"已有现成舱段"，不计时。
func _timed_steps(feasibility: Dictionary) -> int:
	var count := 0
	var solver_path = feasibility.get("solverPath", null)
	if solver_path is Array:
		for step in solver_path:
			if str(step.get("type", "")) != "MATCH":
				count += 1
	return count


func _untimed_steps(feasibility: Dictionary) -> int:
	var count := 0
	var solver_path = feasibility.get("solverPath", null)
	if solver_path is Array:
		for step in solver_path:
			if str(step.get("type", "")) == "MATCH":
				count += 1
	return count


## 消耗一律取 Core 给的 `consumed`（没有就退回 `costLiquid` 记 1 份）；
## B 类订单还要加上 `transferLiquids`。界面不做"够不够"的判断。
func _cost_summary(feasibility: Dictionary) -> String:
	var totals: Dictionary = {}
	var solver_path = feasibility.get("solverPath", null)
	if solver_path is Array:
		for step in solver_path:
			var consumed = step.get("consumed", null)
			if consumed is Dictionary:
				for key in (consumed as Dictionary).keys():
					var name := str(key)
					totals[name] = int(totals.get(name, 0)) + int((consumed as Dictionary)[key])
				continue
			var cost := _text(step.get("costLiquid"))
			if cost != "":
				totals[cost] = int(totals.get(cost, 0)) + 1
	var transferred = feasibility.get("transferLiquids", null)
	if transferred is Dictionary:
		for key in (transferred as Dictionary).keys():
			var name := str(key)
			totals[name] = int(totals.get(name, 0)) + int((transferred as Dictionary)[key])
	var parts: Array[String] = []
	for name in totals.keys():
		parts.append("%s×%d" % [str(name), int(totals[name])])
	return "、".join(parts)


## 风险提示只用 Core 字段：要先迁移、求解器没给出确定结论。
func _risks(feasibility: Dictionary) -> Array[String]:
	var risks: Array[String] = []
	var master_path = feasibility.get("masterPath", null)
	if master_path is Array and not (master_path as Array).is_empty():
		risks.append("这单要先把主台改成可迁移状态（%d 步）" % (master_path as Array).size())
	if bool(feasibility.get("undetermined", false)):
		risks.append("求解器没给出确定结论（undetermined），执行时可能卡住")
	return risks


## 第二层解释：只回答"该去检查哪里"，不承诺"改了就能做"。
## 判据全部来自 state 字段，不解析 `reason` 文字。
func _checklist(feasibility: Dictionary, order: Dictionary) -> Array[String]:
	var tips: Array[String] = []
	var global_state: Dictionary = _state.get("globalState", {}) if _state.get("globalState", null) is Dictionary else {}
	if global_state.get("currentMaster", null) == null:
		tips.append("主装配台还没选")
	var master_path = feasibility.get("masterPath", null)
	if master_path is Array and not (master_path as Array).is_empty() and global_state.get("currentSlave", null) == null:
		tips.append("这单要先迁移，副装配台必须已选")

	var warehouse: Dictionary = _state.get("warehouse", {}) if _state.get("warehouse", null) is Dictionary else {}
	var requirements: Array = order.get("requirements", [])
	var jar_count := int(warehouse.get("jars", 0))
	if jar_count < requirements.size():
		tips.append("仓库舱段 %d 只，需求 %d 件" % [jar_count, requirements.size()])

	var liquids: Dictionary = warehouse.get("liquids", {}) if warehouse.get("liquids", null) is Dictionary else {}
	for requirement in requirements:
		var liquid = requirement.get("liquid", null)
		if liquid == null:
			continue
		tips.append("需要工质 %s（仓库 %d）" % [str(liquid), int(liquids.get(str(liquid), 0))])

	var workshops: Array = _state.get("workshops", []) if _state.get("workshops", null) is Array else []
	for workshop in workshops:
		var ban: Array = workshop.get("ban", []) if workshop.get("ban", null) is Array else []
		for requirement in requirements:
			var liquid = requirement.get("liquid", null)
			if liquid != null and ban.has(liquid):
				tips.append("%s 禁装 %s" % [str(workshop.get("name", "工作台")), str(liquid)])

	var phase := str(_state.get("phase", ""))
	if phase != "" and phase != "setup":
		tips.append("当前是「%s」阶段，只有准备阶段才能开新单" % phase)
	return tips


## DTO 里的可空整数（例如过程中的 `remainingTicks`）不能直接喂给 `int()`：
## `int(null)` 会报 "Nonexistent 'int' constructor" 并打断整块重画。
func _int_or(value: Variant, fallback: int) -> int:
	return int(value) if value != null else fallback
