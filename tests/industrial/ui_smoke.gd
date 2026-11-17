extends SceneTree
## 工业界面（阶段 6）的 headless 冒烟测试。
##
## 它验的是"界面有没有如实反映世界"，不是"好不好看"：
## 布局观感、可读性、手感必须人工试玩，脚本不能代替（03 号文档 §10 最后一句）。
##
## 断言路线：打开 → 看到空态 → 推进一回合 → 派单 → 可行性出现 → 开始 → 记录栏有行。

var checks := 0
var failures: Array[String] = []

var scene: Control
var runtime: Node


func _initialize() -> void:
	print("=== industrial ui smoke ===")
	# 清掉上一次跑留下的玩家存档：否则钱包/工业存档会把断言带偏（实测踩过）。
	for path in ["user://player.cfg", "user://industrial_save.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	runtime = get_root().get_node_or_null("IndustrialRuntime")
	if runtime == null:
		# `--script` 环境不一定加载 autoload：这里自建一份同名节点，走与游戏里相同的路径。
		runtime = load("res://scripts/industrial/runtime/IndustrialRuntime.gd").new()
		runtime.name = "IndustrialRuntime"
		get_root().add_child(runtime)
	runtime.freeze_when_unfocused = false
	runtime.auto_advance = false

	var packed: PackedScene = load("res://scenes/industrial/IndustrialMain.tscn")
	_check(packed != null, "场景 IndustrialMain.tscn 能加载")
	if packed == null:
		_finish()
		return

	# `--script` 环境不装载 autoload：工业界面通过 /root/GameState 取矿石，这里补一个
	if not get_root().has_node("GameState"):
		var gs = load("res://globals/GameState.gd").new()
		gs.name = "GameState"
		get_root().add_child(gs)
		# --script 环境也可能装载 autoload：无条件关闭钱包落盘，避免污染玩家存档
		gs.persist_wallet = false

	scene = packed.instantiate()
	get_root().add_child(scene)
	# 节点要等主循环走一帧才真正进入树；`_ready`（建界面 + 装配世界）发生在那一刻。
	await process_frame

	# ---- 1. 结构 ----
	_check(runtime.running, "打开界面时工业世界已装配")
	_check(_find("TopBar") != null, "顶栏存在")
	_check(_find("BenchCard_Master") != null, "主装配台卡片存在")
	_check(_find("BenchCard_Slave") != null, "副装配台卡片存在")
	_check(_find("LinesPanel") != null, "产线面板存在")
	_check(_find("WarehousePanel") != null, "仓库面板存在")
	_check(_find("OrdersPanel") != null, "工单面板存在")
	_check(_find("LogPanel") != null, "记录面板存在")
	_check(_find("FooterBar/") != null or _find("FooterBar") != null, "底栏存在")

	var turns_text := _label_text("TopBar", "回合")
	_check(turns_text != "", "顶栏显示回合（实际：%s）" % turns_text)
	_check(turns_text.contains("/ 12"), "回合上限来自世界配置（12）")

	# ---- 2. 空态：没有订单时不显示 0 值面板 ----
	var before_orders := _order_count()
	_check(before_orders == 0, "开局没有工单（实际 %d）" % before_orders)

	# ---- 3. 推进一回合 ----
	var advance: Button = _advance_button()
	_check(advance != null, "底栏有「推进一回合」按钮")
	if advance == null:
		_finish()
		return
	_check(not advance.disabled, "「推进一回合」可点")
	var used_before := _used()
	advance.pressed.emit()
	_check(_used() == used_before + 1, "点一次推进，回合 +1（%d → %d）" % [used_before, _used()])

	var log_panel = _find("LogPanel")
	_check(log_panel.frame_count() > 0, "记录栏收到了帧流（%d 帧）" % log_panel.frame_count())
	_check(log_panel.line_count() == 0, "纯生产推进不写过程行（此刻 %d 行）" % log_panel.line_count())

	# ---- 4. 先选主装配台（没有主台时内核一律判"不可行"，这是真实开局步骤）----
	scene._on_picker_requested("master")
	await process_frame
	var picker := _find("Picker_Workshop")
	_check(picker != null and picker.visible, "点「换主台」弹出装配台选择器")
	var picker_list := _find_item_list(picker)
	_check(picker_list != null and picker_list.item_count > 0,
		"选择器列出了可选装配台（%d 台）" % (0 if picker_list == null else picker_list.item_count))
	if picker_list != null and picker_list.item_count > 0:
		picker_list.select(0)
		scene._on_picker_confirm()
		await process_frame
		_check(not scene._master_card.is_empty_workshop(), "确认后主装配台已就位")
	else:
		_fail("选择器里没有装配台，后面的派单没法验")

	# 副台也装上，B 类工单才有机会可行（沙盒世界配了两台）。
	scene._on_picker_requested("slave")
	await process_frame
	var slave_list := _find_item_list(_find("Picker_Workshop"))
	if slave_list != null and slave_list.item_count > 1:
		slave_list.select(1)
		scene._on_picker_confirm()
		await process_frame
	_check(not scene._slave_card.is_empty_workshop(), "副装配台已就位")

	# 推几回合，让产线把舱段送进仓库、再流进装配台。
	for i in range(3):
		advance.pressed.emit()
		await process_frame

	# ---- 5. 派单：随机可能抽到"直接做不了"的模板，挑到能开始的为止 ----
	var startable := {}
	for attempt in range(6):
		scene._on_order_action("random", {})
		await process_frame
		startable = _find_startable_order()
		if not startable.is_empty():
			break

	_check(_order_count() > 0, "随机派单后出现工单卡（%d 张）" % _order_count())
	_check(_any_feasibility_shown(), "工单卡里出现了可行性判定")

	# ---- 5. 开始一单，并推两回合，看记录栏有没有写过程 ----
	if startable.is_empty():
		_fail("六次随机都没派到可开始的工单（沙盒模板里应该有可行的）")
	else:
		scene._on_order_action("start", {"index": int(startable.get("index", 0)), "id": int(startable.get("id", 0))})
		await process_frame
		# 两种合法结局都要认：需要动手的单会留在"执行中"，而直接满足需求的单会在本次调用里
		# 一次走完（Core 的 MATCH 不计时，见 02 号文档 §9）——后者不是缺陷，前提是状态真的变成功。
		var started_order := _order_by_index(int(startable.get("index", 0)))
		var started_status := str(started_order.get("status", ""))
		var has_process := _running_processes() >= 1
		_check(has_process or started_status == "成功",
			"开始后工单要么在执行中、要么已直接完成（状态 %s，过程 %d 个）" % [started_status, _running_processes()])
		if has_process:
			for i in range(2):
				advance.pressed.emit()
				await process_frame
			_check(_find("LogPanel").line_count() > 0, "过程步骤进了记录栏（%d 行）" % _find("LogPanel").line_count())
		else:
			_check(started_status == "成功", "直接完成的工单状态确实是「成功」（%s）" % started_status)

	# ---- 6. 换分辨率不炸：布局容器能重新计算 ----
	get_root().size = Vector2i(1600, 900)
	await process_frame
	_check(_find("Body") != null, "改窗口尺寸后界面结构仍在")

	# ---- 7. 按模板派单（阶段 7「创建订单」这条链路：模板来自世界配置）----
	var orders_before_template := _order_count()
	scene._on_order_action("templates", {})
	await process_frame
	var template_list := _find_item_list(_find("Picker_Workshop"))
	_check(template_list != null and template_list.item_count >= 5,
		"「选模板」列出世界配置的模板（%d 张）" % (0 if template_list == null else template_list.item_count))
	if template_list != null and template_list.item_count > 0:
		template_list.select(0)
		scene._on_picker_confirm()
		await process_frame
		_check(_order_count() == orders_before_template + 1,
			"按模板派单后工单 +1（%d → %d）" % [orders_before_template, _order_count()])
	else:
		_fail("模板选择器里没有列项")

	# ---- 8. 关掉界面再打开：世界不随界面消失（阶段 7 验收第 3 条）----
	var used_snapshot := _used()
	var orders_snapshot := _order_count()
	scene.free()
	await process_frame
	scene = packed.instantiate()
	get_root().add_child(scene)
	await process_frame
	_check(runtime.running, "重开界面后工业世界仍然存活")
	_check(_used() == used_snapshot, "重开界面后回合数不变（%d）" % _used())
	_check(_order_count() == orders_snapshot, "重开界面后工单数不变（%d）" % _order_count())

	# ---- 9. 界面关掉时世界照样生产（阶段 8 的核心：工业生产不依赖 UI 是否打开）----
	# 前面那单已把目标做完（结局"已结算"），Core 会拒绝继续推进 —— 先重开一局拿到可推进的世界。
	runtime.reset_world()
	var restarted: Dictionary = runtime.ensure_started()
	_check(bool(restarted["success"]), "重开一局后世界可继续推进")
	runtime.auto_advance = true
	var used_while_open := _used()
	scene.free()
	await create_timer(2.4).timeout
	var used_while_closed := _used()
	_check(used_while_closed > used_while_open,
		"界面关掉 2.4 秒后仍在推进（回合 %d → %d）" % [used_while_open, used_while_closed])
	runtime.auto_advance = false
	scene = packed.instantiate()
	get_root().add_child(scene)
	await process_frame
	_check(_used() == used_while_closed,
		"重新打开界面看到的是关掉期间的结果（%d）" % _used())

	# ---- 10. 战斗资源投入工业（阶段 9）：花矿石提一档产线速率，矿石扣掉、世界真的变快 ----
	runtime.reset_world()
	runtime.ensure_started()
	_game_state().ore = 5
	scene._apply_state(scene._state)
	var before_line := _rate_of(runtime.get_state(), "一号锻造线", "圆形舱段")
	_check(absf(before_line - 0.4) < 0.001, "开局一号锻造线的圆形舱段速率是 0.4（实测 %s）" % str(before_line))
	scene._on_upgrade_requested("一号锻造线", "圆形舱段", before_line + 0.2, 2)
	var after_line := _rate_of(runtime.get_state(), "一号锻造线", "圆形舱段")
	_check(absf(after_line - 0.6) < 0.001, "投矿后速率升到 0.6（实测 %s）" % str(after_line))
	_check(_game_state().ore == 3, "投矿扣掉 2 矿石（剩 %d）" % _game_state().ore)
	# 矿石不够时不许改世界
	_game_state().ore = 1
	scene._apply_state(scene._state)
	scene._on_upgrade_requested("一号锻造线", "圆形舱段", 0.6, 2)
	_check(absf(_rate_of(runtime.get_state(), "一号锻造线", "圆形舱段") - 0.6) < 0.001, "矿石不够时速率不变")
	_check(_game_state().ore == 1, "矿石不够时不扣矿（剩 %d）" % _game_state().ore)

	# ---- 11. 工单结算发材料、材料强化攻击力（阶段 10）----
	var wallet := _game_state()
	wallet.materials = 1
	scene._refresh_reward_bar()
	_check(_attack_text().contains("材料 1"), "顶栏显示到手 1 张强化材料（实际「%s」）" % _attack_text())
	_check(scene._upgrade_attack_button.disabled, "材料只有 1 张时「强化攻击」是灰的")

	wallet.materials = 3
	scene._refresh_reward_bar()
	_check(not scene._upgrade_attack_button.disabled, "材料 3 张时「强化攻击」可点")
	var level_before := int(wallet.attack_level)
	scene._on_upgrade_attack_pressed()
	_check(int(wallet.attack_level) == level_before + 1,
		"点一次攻击力 +1（%d → %d）" % [level_before, int(wallet.attack_level)])
	_check(int(wallet.materials) == 0, "升级花掉 3 张材料（剩 %d）" % int(wallet.materials))
	_check(int(wallet.attack_damage()) == 1 + int(wallet.attack_level), "子弹伤害跟着等级走（%d）" % int(wallet.attack_damage()))
	_check(_attack_text().contains("攻击 Lv%d" % int(wallet.attack_level)), "顶栏攻击力显示同步（「%s」）" % _attack_text())

	# 结算发奖本身由 reward_smoke 覆盖（这里只验界面把数值画出来、按钮可用性对）
	# 界面确实画出了「投矿」按钮（不是只有 handler 存在）
	_check(_has_button_text(scene, "投矿"), "产线面板上出现了「投矿」提档按钮")

	# ---- 12. A 路线 S1：报价卡、执行中锁定、不可行第二层（08 号文档 §2–§4）----
	runtime.reset_world()
	runtime.ensure_started()
	scene._apply_state(scene._state)

	# 主台还没选时派单 + 检查 → 应在第一层原因之外给出"该去检查哪里"。
	# 固定用「三舱工单」：它需要 3 个不同舱段，开局不可能一次满足，
	# 这样"开始后有执行中的过程"才是稳定可测的（随机单有时会一步跑完、没有过程可锁）。
	runtime.create_order_from_template("三舱工单")
	runtime.check_all_feasibility()
	scene._apply_state(scene._state)
	_check(_all_text(scene).contains("主装配台还没选"), "不可行时给出第二层检查清单（主装配台还没选）")
	_check(_has_button_text(scene, "按此方案执行"), "开始按钮改成「按此方案执行」")

	# 配好主副台、推几回合让仓库有舱段，再让报价出现
	runtime.set_master(0)
	runtime.set_slave(1)
	for i in 4:
		runtime.advance_manual()
	runtime.check_all_feasibility()
	scene._apply_state(scene._state)
	_check(_all_text(scene).contains("报价：计时"), "可行工单上出现报价行（计时步数 · 估算刻数）")

	# 执行中锁定：不去赌"开局是否刚好需要分步"，而是直接喂一份带在册过程的快照。
	# 锁定的判据只有一条——processes 里有未结束的 order_execution。
	var synthetic: Dictionary = runtime.get_state().duplicate(true)
	synthetic["processes"] = [{
		"id": 99, "kind": "order_execution", "subjectId": 3,
		"state": "running", "currentStep": 1, "totalSteps": 3,
		"ticksUntilNextUnit": 1, "remainingTicks": 3,
	}]
	scene._apply_state(synthetic)
	_check(scene._master_card._pick_button.disabled, "执行中「换主台」被禁用")
	_check(scene._orders_panel._pick_template.disabled, "执行中「选模板」被禁用")
	_check(bool(scene._lines_panel._locked), "执行中产线档位与投矿被锁定")
	_check(_has_button_text(scene, "取消"), "执行中工单卡只给「取消」")

	scene._apply_state(runtime.get_state())
	_check(not scene._master_card._pick_button.disabled, "过程结束后「换主台」恢复可用")
	_check(not bool(scene._lines_panel._locked), "过程结束后产线解锁")

	_finish()


# ----------------------------------------------------------------------

func _find(prefix: String) -> Node:
	return _find_recursive(scene, prefix)


func _find_recursive(node: Node, prefix: String) -> Node:
	if node.name.begins_with(prefix):
		return node
	for child in node.get_children():
		var hit := _find_recursive(child, prefix)
		if hit != null:
			return hit
	return null


func _label_text(panel_prefix: String, needle: String) -> String:
	var panel := _find(panel_prefix)
	if panel == null:
		return ""
	var stack: Array[Node] = [panel]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Label and (node as Label).text.contains(needle):
			return (node as Label).text
		for child in node.get_children():
			stack.append(child)
	return ""


func _find_item_list(root_node: Node) -> ItemList:
	if root_node == null:
		return null
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is ItemList:
			return node as ItemList
		for child in node.get_children():
			stack.append(child)
	return null


func _advance_button() -> Button:
	var bar := _find("FooterBar")
	if bar == null:
		return null
	var stack: Array[Node] = [bar]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Button and (node as Button).text == "推进一回合":
			return node
		for child in node.get_children():
			stack.append(child)
	return null


func _order_count() -> int:
	return (runtime.get_state().get("orders", []) as Array).size()


func _used() -> int:
	return int((runtime.get_state().get("turns", {}) as Dictionary).get("used", -1))


func _running_processes() -> int:
	var count := 0
	for process in runtime.get_state().get("processes", []):
		if str(process.get("kind", "")) == "order_execution":
			count += 1
	return count


func _any_feasibility_shown() -> bool:
	var panel := _find("OrdersPanel")
	if panel == null:
		return false
	var stack: Array[Node] = [panel]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Label:
			var text := (node as Label).text
			if text.contains("现在就能直接用上的") or text.contains("不可行") or text.contains("可行性"):
				return true
		for child in node.get_children():
			stack.append(child)
	return false


func _find_startable_order() -> Dictionary:
	var fallback := {}
	for order in runtime.get_state().get("orders", []):
		var feasibility = order.get("feasibilityResult", null)
		if feasibility == null:
			continue
		if not bool((feasibility as Dictionary).get("feasible", false)) or str(order.get("status", "")) != "待执行":
			continue
		if fallback.is_empty():
			fallback = order
		# 直接可用量 < 需求条数 才代表"还要动手"，也才跑得出分步过程。
		var direct := float((feasibility as Dictionary).get("directCount", 0.0))
		if direct < float((order.get("requirements", []) as Array).size()):
			return order
	return fallback


func _order_by_index(index: int) -> Dictionary:
	for order in runtime.get_state().get("orders", []):
		if int(order.get("index", -1)) == index:
			return order
	return {}


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  PASS  ", label)
	else:
		failures.append(label)
		print("  FAIL  ", label)


func _fail(label: String) -> void:
	_check(false, label)


## 整棵界面的可见文字拼起来（断言"某句话出现过"，不依赖具体节点路径）。
func _all_text(node: Node) -> String:
	var parts: Array[String] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is Label:
			parts.append((current as Label).text)
		elif current is Button:
			parts.append((current as Button).text)
		for child in current.get_children():
			stack.append(child)
	return "\n".join(parts)


## 场景里是否存在文本以 prefix 开头的按钮（用来确认界面真的画出了入口，而不是只有 handler）
func _has_button_text(node: Node, prefix: String) -> bool:
	if node is Button and (node as Button).text.begins_with(prefix):
		return true
	for child in node.get_children():
		if _has_button_text(child, prefix):
			return true
	return false


## 从状态快照里读某条产线的速率：producerStatus.producers[].rates[形状]
## 顶栏材料/攻击那一排的文本（找不到节点时给空串，断言会明确失败）。
func _attack_text() -> String:
	var label = scene._attack_label
	var mat = scene._material_label
	return "%s %s" % ["" if mat == null else mat.text, "" if label == null else label.text]


func _game_state() -> Node:
	return get_root().get_node("GameState")


func _rate_of(state: Dictionary, producer_name: String, shape: String) -> float:
	for producer in state.get("producerStatus", {}).get("producers", []):
		if str(producer.get("name", "")) != producer_name:
			continue
		return float(producer.get("rates", {}).get(shape, 0.0))
	return -1.0


func _finish() -> void:
	print("=== %d 项检查，%d 项失败 ===" % [checks, failures.size()])
	for item in failures:
		print("  - ", item)
	# 退出前把场景与运行时节点收掉，免得 Godot 报一堆 "leaked at exit" 噪音。
	if scene != null and is_instance_valid(scene):
		scene.free()
	if runtime != null and is_instance_valid(runtime):
		runtime.free()
	quit(0 if failures.is_empty() else 1)
