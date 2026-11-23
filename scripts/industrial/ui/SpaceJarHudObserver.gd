extends Control
## Live, read-only view of the active World V2 snapshot.
## This component never issues Jar commands and never infers feasibility.

const UiKit := preload("res://scripts/industrial/ui/UiKit.gd")
const ShapeVisuals := preload("res://scripts/industrial/ui/ShapeVisuals.gd")

var _host: Node
var _elapsed := 0.0
var _expanded := false
var _toggle: Button
var _panel: PanelContainer
var _resource_jars: HBoxContainer
var _resource_liquids: HBoxContainer
var _master_box: VBoxContainer
var _slave_box: VBoxContainer
var _demands_box: VBoxContainer
var _status: Label
var _last_signature := ""
var _previous_snapshot: Dictionary = {}
var _feedback_label: Label
var _feedback_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_refresh_snapshot()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.25:
		return
	_elapsed = 0.0
	_refresh_snapshot()

func _build() -> void:
	_toggle = UiKit.button("JAR  ·  等待世界", 260)
	_toggle.position = Vector2(20, 66)
	_toggle.custom_minimum_size = Vector2(260, 34)
	_toggle.tooltip_text = "点击展开飞船 Jar、液体、主从工作台与订单的实时只读状态。"
	_toggle.pressed.connect(_toggle_expanded)
	add_child(_toggle)

	_feedback_label = UiKit.label("", UiKit.FONT_SMALL, UiKit.ACCENT)
	_feedback_label.position = Vector2(292, 72)
	_feedback_label.custom_minimum_size = Vector2(420, 28)
	_feedback_label.modulate.a = 0.0
	_feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feedback_label)

	_panel = UiKit.panel("JarObserverPanel", UiKit.PANEL)
	_panel.position = Vector2(20, 106)
	_panel.custom_minimum_size = Vector2(460, 360)
	_panel.size = Vector2(460, 360)
	_panel.visible = false
	add_child(_panel)

	var column := UiKit.vbox(8)
	_status = UiKit.label("Jar 世界尚未启动", UiKit.FONT_SMALL, UiKit.MUTED)
	column.add_child(_status)

	column.add_child(UiKit.title("飞船资源"))
	_resource_jars = UiKit.hbox(8)
	column.add_child(_resource_jars)
	_resource_liquids = UiKit.hbox(8)
	column.add_child(_resource_liquids)

	column.add_child(UiKit.title("工作台"))
	_master_box = UiKit.vbox(3)
	column.add_child(_master_box)
	_slave_box = UiKit.vbox(3)
	column.add_child(_slave_box)

	column.add_child(UiKit.title("订单 / 冷却"))
	_demands_box = UiKit.vbox(3)
	column.add_child(_demands_box)
	var scroll := UiKit.scroll(column, 340)
	_panel.add_child(scroll)

func _toggle_expanded() -> void:
	_expanded = not _expanded
	_panel.visible = _expanded
	if _expanded:
		_refresh_snapshot()

func _refresh_snapshot() -> void:
	if _host == null or not is_instance_valid(_host):
		_host = get_node_or_null("/root/WorldV2ShipHost")
	if _host == null or not _host.has_method("GetWorldSnapshot"):
		_set_unavailable("Jar 世界未连接")
		return
	var snapshot: Variant = _host.call("GetWorldSnapshot")
	if not (snapshot is Dictionary) or not bool(snapshot.get("available", false)):
		_set_unavailable("Jar 世界未启动")
		return
	var order_presentation: Dictionary = {}
	var game := get_node_or_null("/root/Game")
	if game != null and game.has_method("get_order_presentation_metadata"):
		var raw_presentation: Variant = game.call("get_order_presentation_metadata")
		if raw_presentation is Dictionary:
			order_presentation = raw_presentation
	var signature := JSON.stringify({"snapshot": snapshot, "orderPresentation": order_presentation})
	if signature == _last_signature:
		return
	_emit_snapshot_feedback(snapshot)
	_last_signature = signature
	var jars: Variant = snapshot.get("resourceJars", [])
	var liquids: Variant = snapshot.get("resourceLiquids", {})
	var master: Variant = snapshot.get("master", {})
	var slave: Variant = snapshot.get("slave", {})
	var demands: Variant = snapshot.get("demands", [])
	var jar_count := jars.size() if jars is Array else 0
	var liquid_total := 0
	if liquids is Dictionary:
		for value in liquids.values():
			liquid_total += int(value)
	var lifecycle := String(snapshot.get("lifecycleState", ""))
	_toggle.text = "JAR  ·  %d 罐  ·  %d 份液体  ·  %s" % [jar_count, liquid_total, _lifecycle_text(lifecycle)]
	_status.text = "世界时间 %d ms  ·  逻辑时间 %d ms" % [int(snapshot.get("worldTimeMilli", 0)), int(snapshot.get("logicalTimeMilli", 0))]
	_render_resource_jars(jars)
	_render_resource_liquids(liquids)
	_render_workshop(_master_box, "主台", master)
	_render_workshop(_slave_box, "从台", slave)
	_render_demands(demands, snapshot.get("activeSessions", []), order_presentation)

func _set_unavailable(message: String) -> void:
	_last_signature = ""
	_previous_snapshot.clear()
	_toggle.text = "JAR  ·  " + message
	_status.text = message
	UiKit.clear_children(_resource_jars)
	UiKit.clear_children(_resource_liquids)
	UiKit.clear_children(_master_box)
	UiKit.clear_children(_slave_box)
	UiKit.clear_children(_demands_box)


## Compare detached Host snapshots. This is presentation feedback only:
## no inferred feasibility, resource mutation, or UI-owned simulation clock.
func _emit_snapshot_feedback(snapshot: Dictionary) -> void:
	if _previous_snapshot.is_empty():
		_previous_snapshot = snapshot.duplicate(true)
		return
	var events: Array[String] = []
	var old_lifecycle := String(_previous_snapshot.get("lifecycleState", ""))
	var new_lifecycle := String(snapshot.get("lifecycleState", ""))
	if old_lifecycle != new_lifecycle and not new_lifecycle.is_empty():
		events.append("世界状态：" + _lifecycle_text(new_lifecycle))
	var old_jars: Variant = _previous_snapshot.get("resourceJars", [])
	var new_jars: Variant = snapshot.get("resourceJars", [])
	var old_jar_count := old_jars.size() if old_jars is Array else 0
	var new_jar_count := new_jars.size() if new_jars is Array else 0
	if new_jar_count != old_jar_count:
		var delta := new_jar_count - old_jar_count
		events.append(("获得" if delta > 0 else "消耗") + " Jar ×%d" % absi(delta))
	var old_filled := _filled_jar_count(old_jars)
	var new_filled := _filled_jar_count(new_jars)
	if new_filled != old_filled:
		var delta := new_filled - old_filled
		events.append(("Jar 装液 +" if delta > 0 else "Jar 空置 ") + "%d" % absi(delta))
	var liquid_delta := _dictionary_total(snapshot.get("resourceLiquids", {})) - _dictionary_total(_previous_snapshot.get("resourceLiquids", {}))
	if liquid_delta != 0:
		events.append(("飞船液体 +" if liquid_delta > 0 else "飞船液体 ") + "%d" % absi(liquid_delta))
	for key in ["master", "slave"]:
		var before: Variant = _previous_snapshot.get(key, {})
		var after: Variant = snapshot.get(key, {})
		if before is Dictionary and after is Dictionary:
			var delta := _dictionary_total(after.get("liquids", {})) - _dictionary_total(before.get("liquids", {}))
			if delta != 0:
				var role := "主台" if key == "master" else "从台"
				events.append("%s暂存 %s%d" % [role, "+" if delta > 0 else "−", absi(delta)])
		var old_jars_in_bench := before.get("jars", []) if before is Dictionary else []
		var new_jars_in_bench := after.get("jars", []) if after is Dictionary else []
		var old_bench_filled := _filled_jar_count(old_jars_in_bench)
		var new_bench_filled := _filled_jar_count(new_jars_in_bench)
		if new_bench_filled != old_bench_filled:
			var role := "主台" if key == "master" else "从台"
			events.append("%s装液 Jar %s%d" % [role, "+" if new_bench_filled > old_bench_filled else "−", absi(new_bench_filled - old_bench_filled)])
	var old_cooling := _cooling_demand_ids(_previous_snapshot.get("demands", []))
	var new_cooling := _cooling_demand_ids(snapshot.get("demands", []))
	for demand_id in new_cooling:
		if not old_cooling.has(demand_id):
			events.append("订单 #%s 进入冷却" % demand_id)
	for demand_id in old_cooling:
		if not new_cooling.has(demand_id):
			events.append("订单 #%s 冷却结束" % demand_id)
	var step_delta := _active_session_step_total(snapshot.get("activeSessions", [])) - _active_session_step_total(_previous_snapshot.get("activeSessions", []))
	if step_delta > 0:
		events.append("订单推进 %d 步" % step_delta)
	_previous_snapshot = snapshot.duplicate(true)
	if events.is_empty():
		return
	var visible_events: Array[String] = []
	for i in mini(events.size(), 2):
		visible_events.append(events[i])
	if events.size() > 2:
		visible_events.append("另有 %d 项变化" % (events.size() - 2))
	_show_feedback("　·　".join(visible_events), Color("e5b85f") if events.any(func(value: String) -> bool: return "消耗" in value or "冷却" in value or "空置" in value) else Color("6fd1ae"))

func _show_feedback(message: String, tint: Color) -> void:
	_feedback_label.text = message
	_feedback_label.add_theme_color_override("font_color", tint)
	_feedback_label.modulate = Color(1, 1, 1, 1)
	_toggle.modulate = tint
	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_feedback_tween = create_tween()
	_feedback_tween.tween_property(_toggle, "modulate", Color.WHITE, 0.35)
	_feedback_tween.parallel().tween_interval(1.8)
	_feedback_tween.tween_property(_feedback_label, "modulate:a", 0.0, 0.65)

func _filled_jar_count(raw_jars: Variant) -> int:
	var count := 0
	if raw_jars is Array:
		for jar in raw_jars:
			if jar is Dictionary and not String(jar.get("liquid", "")).is_empty():
				count += 1
	return count

func _dictionary_total(raw: Variant) -> int:
	var total := 0
	if raw is Dictionary:
		for value in raw.values():
			total += int(value)
	return total

func _cooling_demand_ids(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw is Array:
		for demand in raw:
			if demand is Dictionary and bool(demand.get("isCoolingDown", false)):
				result.append(String(demand.get("id", "")))
	return result

func _active_session_step_total(raw: Variant) -> int:
	var total := 0
	if raw is Array:
		for session in raw:
			if session is Dictionary and not bool(session.get("isTerminal", false)):
				total += int(session.get("completedMasterSteps", 0)) + int(session.get("completedSlaveSteps", 0))
	return total

func _render_resource_jars(raw_jars: Variant) -> void:
	UiKit.clear_children(_resource_jars)
	if not (raw_jars is Array) or raw_jars.is_empty():
		_resource_jars.add_child(UiKit.label("舱段库存：0", UiKit.FONT_SMALL, UiKit.MUTED))
		return
	var counts := {}
	var filled_by_shape := {}
	for jar in raw_jars:
		if jar is Dictionary:
			var shape := String(jar.get("shape", ""))
			counts[shape] = int(counts.get(shape, 0)) + 1
			if not String(jar.get("liquid", "")).is_empty():
				filled_by_shape[shape] = int(filled_by_shape.get(shape, 0)) + 1
	for shape in counts:
		var filled := int(filled_by_shape.get(shape, 0))
		_resource_jars.add_child(_shape_token(String(shape), "×%d · 装液%d" % [int(counts[shape]), filled]))

func _render_resource_liquids(raw_liquids: Variant) -> void:
	UiKit.clear_children(_resource_liquids)
	if not (raw_liquids is Dictionary) or raw_liquids.is_empty():
		_resource_liquids.add_child(UiKit.label("液体库存：0", UiKit.FONT_SMALL, UiKit.MUTED))
		return
	for liquid in raw_liquids:
		_resource_liquids.add_child(UiKit.label("%s  %d" % [String(liquid), int(raw_liquids[liquid])], UiKit.FONT_SMALL, ShapeVisuals.liquid_color_for(String(liquid))))

func _render_workshop(parent: VBoxContainer, role: String, raw_workshop: Variant) -> void:
	UiKit.clear_children(parent)
	if not (raw_workshop is Dictionary) or raw_workshop.is_empty():
		parent.add_child(UiKit.label("%s：未配置" % role, UiKit.FONT_SMALL, UiKit.MUTED))
		return
	var workshop: Dictionary = raw_workshop
	var base: Array = workshop.get("baseMarks", [])
	var extra: Array = workshop.get("additionalMarks", [])
	var jars: Array = workshop.get("jars", [])
	var liquids: Dictionary = workshop.get("liquids", {})
	var accent := ShapeVisuals.blend_marks(base, extra)
	var title := UiKit.label("%s · %s   舱段 %d / %d" % [role, String(workshop.get("name", "")), jars.size(), int(workshop.get("maxJars", 0))], UiKit.FONT_BODY, accent)
	parent.add_child(title)
	var marks := UiKit.hbox(6)
	parent.add_child(marks)
	for shape in base:
		marks.add_child(_shape_token(String(shape), "基础"))
	for shape in extra:
		marks.add_child(_shape_token(String(shape), "附加"))
	var by_shape := {}
	var filled_by_shape := {}
	for jar in jars:
		if jar is Dictionary:
			var shape := String(jar.get("shape", ""))
			by_shape[shape] = int(by_shape.get(shape, 0)) + 1
			if not String(jar.get("liquid", "")).is_empty():
				filled_by_shape[shape] = int(filled_by_shape.get(shape, 0)) + 1
	if not by_shape.is_empty():
		var jar_row := UiKit.hbox(6)
		parent.add_child(jar_row)
		for shape in by_shape:
			var filled := int(filled_by_shape.get(shape, 0))
			var detail := "×%d · 装液%d" % [int(by_shape[shape]), filled]
			jar_row.add_child(_shape_token(String(shape), detail))
	var liquid_row := UiKit.vbox(3)
	parent.add_child(liquid_row)
	var liquid_capacity := int(workshop.get("maxLiquids", 0))
	for liquid in liquids:
		var liquid_line := UiKit.hbox(6)
		liquid_row.add_child(liquid_line)
		var amount := int(liquids[liquid])
		var liquid_label := UiKit.label("%s %d / %d" % [String(liquid), amount, liquid_capacity], UiKit.FONT_SMALL, UiKit.TEXT)
		liquid_label.custom_minimum_size.x = 130
		liquid_line.add_child(liquid_label)
		if liquid_capacity > 0:
			var meter := ProgressBar.new()
			meter.min_value = 0
			meter.max_value = liquid_capacity
			meter.value = clampi(amount, 0, liquid_capacity)
			meter.show_percentage = false
			meter.custom_minimum_size = Vector2(150, 9)
			meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ShapeVisuals.apply_meter_style(meter, ShapeVisuals.liquid_color_for(String(liquid)))
			liquid_line.add_child(meter)
	var bans: Array = workshop.get("ban", [])
	if not bans.is_empty():
		var ban_names: Array[String] = []
		for ban in bans:
			ban_names.append(String(ban))
		parent.add_child(UiKit.label("禁令：%s" % "、".join(ban_names), UiKit.FONT_SMALL, UiKit.WARN))

func _render_demands(raw_demands: Variant, raw_sessions: Variant, order_presentation: Dictionary) -> void:
	UiKit.clear_children(_demands_box)
	if not (raw_demands is Array) or raw_demands.is_empty():
		_demands_box.add_child(UiKit.label("当前没有订单", UiKit.FONT_SMALL, UiKit.MUTED))
		return
	for demand in raw_demands:
		if not (demand is Dictionary):
			continue
		var row := UiKit.hbox(6)
		_demands_box.add_child(row)
		var cooling := bool(demand.get("isCoolingDown", false))
		var remaining := int(demand.get("cooldownRemainingLogicalMilli", 0))
		var order_key := String(demand.get("orderDefinitionKey", ""))
		var metadata: Dictionary = order_presentation.get(order_key, {})
		var primary_shape := String(metadata.get("primaryShape", ""))
		var heading := UiKit.label("%s  #%d" % [order_key if not order_key.is_empty() else String(demand.get("type", "订单")), int(demand.get("id", 0))], UiKit.FONT_SMALL, ShapeVisuals.color_for(primary_shape) if not primary_shape.is_empty() else (UiKit.WARN if cooling else UiKit.TEXT))
		row.add_child(heading)
		if not primary_shape.is_empty():
			row.add_child(_shape_token(primary_shape, "主形"))
		row.add_child(UiKit.label("冷却 %d ms" % remaining if cooling else "就绪", UiKit.FONT_SMALL, UiKit.MUTED if cooling else UiKit.OK))
		var requirements: Variant = demand.get("requirements", [])
		if requirements is Array:
			for requirement in requirements:
				if requirement is Dictionary:
					row.add_child(_shape_token(String(requirement.get("shape", "")), "液体" if not String(requirement.get("liquid", "")).is_empty() else "空"))
	if not (raw_sessions is Array):
		return
	for session in raw_sessions:
		if session is Dictionary and not bool(session.get("isTerminal", false)):
			_demands_box.add_child(UiKit.label("执行中 · %s · 主台步 %d / 从台步 %d" % [String(session.get("stage", "")), int(session.get("completedMasterSteps", 0)), int(session.get("completedSlaveSteps", 0))], UiKit.FONT_SMALL, UiKit.ACCENT))

func _shape_token(shape: String, detail: String) -> Label:
	var label := UiKit.label("%s %s %s" % [ShapeVisuals.glyph_for(shape), shape, detail], UiKit.FONT_SMALL, ShapeVisuals.color_for(shape))
	label.tooltip_text = "Jar 形状：%s" % shape
	return label

func _lifecycle_text(value: String) -> String:
	match value:
		"Active": return "运行"
		"Paused": return "暂停"
		"Faulted": return "故障"
		"Disposed": return "已结束"
		_: return value if not value.is_empty() else "未启动"
