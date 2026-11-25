extends Control
## Live, read-only view of the active World V2 snapshot.
## The only command it forwards is an explicit Active-demand trigger; Core owns feasibility and execution.

const UiKit := preload("res://scripts/industrial/ui/UiKit.gd")
const ShapeVisuals := preload("res://scripts/industrial/ui/ShapeVisuals.gd")

var _host: Node
var _elapsed := 0.0
var _expanded := false
var _toggle: Button
var _strip_panel: PanelContainer
var _jar_total_label: Label
var _shape_counts: HBoxContainer
var _liquid_counts: HBoxContainer
var _workshop_status: Label
var _lifecycle_status: Label
var _active_dock: PanelContainer
var _active_order_slots: HFlowContainer
var _passive_dock: PanelContainer
var _passive_order_slots: HFlowContainer
var _panel: PanelContainer
var _resource_jars: HFlowContainer
var _resource_liquids: HBoxContainer
var _master_box: VBoxContainer
var _slave_box: VBoxContainer
var _demands_box: VBoxContainer
var _status: Label
var _last_signature := ""
var _summary_base_text := "JAR  ·  等待世界"
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
	_strip_panel = PanelContainer.new()
	_strip_panel.position = Vector2(20, 62)
	_strip_panel.custom_minimum_size = Vector2(960, 34)
	_strip_panel.size = Vector2(960, 34)
	var strip_style := StyleBoxFlat.new()
	strip_style.bg_color = Color("101923")
	strip_style.border_color = Color("35475b")
	strip_style.set_border_width_all(1)
	strip_style.set_corner_radius_all(5)
	strip_style.set_content_margin_all(8)
	_strip_panel.add_theme_stylebox_override("panel", strip_style)
	_strip_panel.tooltip_text = "持续可见的战斗资源状态栏。数量来自 Host 快照；点击右侧详情查看 Jar 与工作台明细。"
	add_child(_strip_panel)
	var strip_row := UiKit.hbox(10)
	_strip_panel.add_child(strip_row)
	_jar_total_label = UiKit.label("JAR  —", UiKit.FONT_BODY, UiKit.TEXT)
	strip_row.add_child(_jar_total_label)
	_shape_counts = UiKit.hbox(7)
	strip_row.add_child(_shape_counts)
	strip_row.add_child(UiKit.label("│", UiKit.FONT_SMALL, UiKit.MUTED))
	_liquid_counts = UiKit.hbox(7)
	strip_row.add_child(_liquid_counts)
	strip_row.add_child(UiKit.spacer())
	_workshop_status = UiKit.label("主台 —  →  从台 —", UiKit.FONT_SMALL, UiKit.MUTED)
	strip_row.add_child(_workshop_status)
	_lifecycle_status = UiKit.label("未启动", UiKit.FONT_SMALL, UiKit.MUTED)
	strip_row.add_child(_lifecycle_status)
	_toggle = UiKit.small_button("详情 ▼", 72)
	_toggle.pressed.connect(_toggle_expanded)
	strip_row.add_child(_toggle)

	# Active orders occupy the bottom-right skill-bar position, leaving objective text at bottom-left.
	_active_dock = PanelContainer.new()
	_active_dock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_active_dock.offset_left = -620
	_active_dock.offset_top = -120
	_active_dock.offset_right = -20
	_active_dock.offset_bottom = -20
	_active_dock.custom_minimum_size = Vector2(600, 100)
	var active_style := StyleBoxFlat.new()
	active_style.bg_color = Color("101923", 0.92)
	active_style.border_color = Color("3b86a8")
	active_style.set_border_width_all(1)
	active_style.set_corner_radius_all(6)
	active_style.set_content_margin_all(6)
	_active_dock.add_theme_stylebox_override("panel", active_style)
	add_child(_active_dock)
	var active_column := UiKit.vbox(3)
	_active_dock.add_child(active_column)
	active_column.add_child(UiKit.label("主动技能 · 主动订单", UiKit.FONT_SMALL, UiKit.ACCENT))
	_active_order_slots = HFlowContainer.new()
	_active_order_slots.add_theme_constant_override("h_separation", 6)
	_active_order_slots.add_theme_constant_override("v_separation", 4)
	active_column.add_child(_active_order_slots)

	# Passive orders are persistent status badges, separated from activatable slots.
	_passive_dock = PanelContainer.new()
	_passive_dock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_passive_dock.offset_left = -270
	_passive_dock.offset_top = 66
	_passive_dock.offset_right = -20
	_passive_dock.offset_bottom = 156
	_passive_dock.custom_minimum_size = Vector2(250, 90)
	_passive_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var passive_style := StyleBoxFlat.new()
	passive_style.bg_color = Color("101923", 0.88)
	passive_style.border_color = Color("8a78b8")
	passive_style.set_border_width_all(1)
	passive_style.set_corner_radius_all(6)
	passive_style.set_content_margin_all(6)
	_passive_dock.add_theme_stylebox_override("panel", passive_style)
	add_child(_passive_dock)
	var passive_column := UiKit.vbox(3)
	_passive_dock.add_child(passive_column)
	passive_column.add_child(UiKit.label("被动技能 · 被动订单", UiKit.FONT_SMALL, Color("b69af7")))
	_passive_order_slots = HFlowContainer.new()
	_passive_order_slots.add_theme_constant_override("h_separation", 5)
	_passive_order_slots.add_theme_constant_override("v_separation", 3)
	_passive_order_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	passive_column.add_child(_passive_order_slots)

	_feedback_label = UiKit.label("", UiKit.FONT_SMALL, UiKit.ACCENT)
	_feedback_label.position = Vector2(20, 98)
	_feedback_label.custom_minimum_size = Vector2(720, 18)
	_feedback_label.modulate.a = 0.0
	_feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feedback_label)

	_panel = UiKit.panel("JarObserverPanel", UiKit.PANEL)
	_panel.position = Vector2(20, 120)
	_panel.custom_minimum_size = Vector2(620, 360)
	_panel.size = Vector2(620, 360)
	_panel.visible = false
	add_child(_panel)

	var column := UiKit.vbox(8)
	_status = UiKit.label("Jar 世界尚未启动", UiKit.FONT_SMALL, UiKit.MUTED)
	column.add_child(_status)

	column.add_child(UiKit.title("飞船资源"))
	_resource_jars = HFlowContainer.new()
	_resource_jars.add_theme_constant_override("h_separation", 6)
	_resource_jars.add_theme_constant_override("v_separation", 6)
	column.add_child(_resource_jars)
	_resource_liquids = UiKit.hbox(8)
	column.add_child(_resource_liquids)

	column.add_child(UiKit.title("工作台"))
	_master_box = UiKit.vbox(3)
	column.add_child(_master_box)
	var transfer_hint := UiKit.label("资源方向  主台  ─────▶  从台   ·   从台只接收主台提供的液体", UiKit.FONT_SMALL, UiKit.ACCENT)
	column.add_child(transfer_hint)
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
	_toggle.text = "详情 ▲" if _expanded else "详情 ▼"
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
	_status.text = "世界时间 %d ms  ·  逻辑时间 %d ms" % [int(snapshot.get("worldTimeMilli", 0)), int(snapshot.get("logicalTimeMilli", 0))]
	var visual_snapshot: Dictionary = snapshot.duplicate(true)
	visual_snapshot.erase("worldTimeMilli")
	visual_snapshot.erase("logicalTimeMilli")
	var signature := JSON.stringify({"snapshot": visual_snapshot, "orderPresentation": order_presentation})
	if signature == _last_signature:
		return
	_emit_snapshot_feedback(snapshot)
	_last_signature = signature
	var jars: Variant = snapshot.get("resourceJars", [])
	var ship_liquid_inventory: Variant = snapshot.get("shipLiquidInventory", {})
	var liquids: Variant = ship_liquid_inventory.get("balances", {}) if ship_liquid_inventory is Dictionary else {}
	var liquid_capacity := int(ship_liquid_inventory.get("capacity", 0)) if ship_liquid_inventory is Dictionary else 0
	var master: Variant = snapshot.get("master", {})
	var slave: Variant = snapshot.get("slave", {})
	var demands: Variant = snapshot.get("demands", [])
	_summary_base_text = _build_hud_resource_line(jars, liquids, liquid_capacity, master, slave, String(snapshot.get("lifecycleState", "")))
	_render_hud_resource_strip(jars, liquids, liquid_capacity, master, slave, String(snapshot.get("lifecycleState", "")))
	_toggle.text = "详情 ▲" if _expanded else "详情 ▼"
	_strip_panel.tooltip_text = _summary_base_text
	_render_resource_jars(jars)
	_render_resource_liquids(liquids, liquid_capacity)
	_render_workshop(_master_box, "主台", master)
	_render_workshop(_slave_box, "从台", slave)
	_render_order_skill_hud(demands, snapshot.get("activeSessions", []), order_presentation)
	_render_demands(demands, snapshot.get("activeSessions", []), order_presentation)


## Persistent combat resource strip. Liquid balances and capacity come from the ship inventory account.
func _build_hud_resource_line(raw_jars: Variant, raw_liquids: Variant, liquid_capacity: int, master: Variant, slave: Variant, lifecycle: String) -> String:
	var jar_list: Array = raw_jars if raw_jars is Array else []
	var jar_shapes: Dictionary = {}
	for jar in jar_list:
		if jar is Dictionary:
			var shape := String(jar.get("shape", "未知"))
			jar_shapes[shape] = int(jar_shapes.get(shape, 0)) + 1
	var shape_parts: Array[String] = []
	for shape in jar_shapes:
		shape_parts.append("%s×%d" % [ShapeVisuals.glyph_for(String(shape)), int(jar_shapes[shape])])
	var liquid_parts: Array[String] = []
	var liquid_total := 0
	if raw_liquids is Dictionary:
		for liquid in raw_liquids:
			var amount := int(raw_liquids[liquid])
			liquid_total += amount
			liquid_parts.append("%s %d" % [String(liquid), amount])
	var liquid_capacity_text := "%d/%d" % [liquid_total, liquid_capacity] if liquid_capacity > 0 else str(liquid_total)
	return "JAR  %d  %s    飞船液体 %s  %s    主台 %s  →  从台 %s    %s" % [
		jar_list.size(),
		" / ".join(shape_parts) if not shape_parts.is_empty() else "无",
		liquid_capacity_text,
		" / ".join(liquid_parts) if not liquid_parts.is_empty() else "无",
		_workshop_hud_summary(master),
		_workshop_hud_summary(slave),
		_lifecycle_text(lifecycle)
	]


func _render_hud_resource_strip(raw_jars: Variant, raw_liquids: Variant, liquid_capacity: int, master: Variant, slave: Variant, lifecycle: String) -> void:
	var jars: Array = raw_jars if raw_jars is Array else []
	_jar_total_label.text = "JAR  %d罐 · %d装液" % [jars.size(), _filled_jar_count(jars)]
	UiKit.clear_children(_shape_counts)
	var counts: Dictionary = {}
	for jar in jars:
		if jar is Dictionary:
			var shape := String(jar.get("shape", "未知"))
			counts[shape] = int(counts.get(shape, 0)) + 1
	for shape in counts:
		_shape_counts.add_child(UiKit.label("%s %d" % [ShapeVisuals.glyph_for(String(shape)), int(counts[shape])], UiKit.FONT_BODY, ShapeVisuals.color_for(String(shape))))
	UiKit.clear_children(_liquid_counts)
	var liquid_total := _dictionary_total(raw_liquids)
	var liquid_capacity_text := "%d/%d" % [liquid_total, liquid_capacity] if liquid_capacity > 0 else str(liquid_total)
	_liquid_counts.add_child(UiKit.label("液体 %s" % liquid_capacity_text, UiKit.FONT_SMALL, UiKit.ACCENT))
	if raw_liquids is Dictionary:
		for liquid in raw_liquids:
			_liquid_counts.add_child(UiKit.label("%s %d" % [String(liquid), int(raw_liquids[liquid])], UiKit.FONT_SMALL, ShapeVisuals.liquid_color_for(String(liquid))))
	_workshop_status.text = "主台 %s  →  从台 %s" % [_workshop_hud_summary(master), _workshop_hud_summary(slave)]
	_lifecycle_status.text = _lifecycle_text(lifecycle)
	_lifecycle_status.add_theme_color_override("font_color", UiKit.WARN if lifecycle == "Faulted" else (UiKit.OK if lifecycle == "Active" else UiKit.MUTED))

func _workshop_hud_summary(raw_workshop: Variant) -> String:
	if not (raw_workshop is Dictionary) or raw_workshop.is_empty():
		return "未配置"
	var workshop: Dictionary = raw_workshop
	var jars: Variant = workshop.get("jars", [])
	var liquids: Variant = workshop.get("liquids", {})
	var jar_count: int = jars.size() if jars is Array else 0
	return "%d罐/%d液" % [jar_count, _dictionary_total(liquids)]

func _set_unavailable(message: String) -> void:
	_last_signature = ""
	_previous_snapshot.clear()
	_summary_base_text = "JAR  ·  " + message
	_toggle.text = "详情 ▲" if _expanded else "详情 ▼"
	_jar_total_label.text = "JAR  —"
	UiKit.clear_children(_shape_counts)
	UiKit.clear_children(_liquid_counts)
	_workshop_status.text = "主台 —  →  从台 —"
	_lifecycle_status.text = message
	UiKit.clear_children(_active_order_slots)
	UiKit.clear_children(_passive_order_slots)
	_active_order_slots.add_child(UiKit.label(message, UiKit.FONT_SMALL, UiKit.MUTED))
	_passive_order_slots.add_child(UiKit.label(message, UiKit.FONT_SMALL, UiKit.MUTED))
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
	var old_jar_count: int = old_jars.size() if old_jars is Array else 0
	var new_jar_count: int = new_jars.size() if new_jars is Array else 0
	if new_jar_count != old_jar_count:
		var delta := new_jar_count - old_jar_count
		events.append(("获得" if delta > 0 else "消耗") + " Jar ×%d" % absi(delta))
	var old_filled := _filled_jar_count(old_jars)
	var new_filled := _filled_jar_count(new_jars)
	if new_filled != old_filled:
		var delta := new_filled - old_filled
		events.append(("Jar 装液 +" if delta > 0 else "Jar 空置 ") + "%d" % absi(delta))
	var liquid_delta := _dictionary_total(_ship_liquid_balances(snapshot)) - _dictionary_total(_ship_liquid_balances(_previous_snapshot))
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
		var old_jars_in_bench: Variant = before.get("jars", []) if before is Dictionary else []
		var new_jars_in_bench: Variant = after.get("jars", []) if after is Dictionary else []
		var old_bench_count: int = old_jars_in_bench.size() if old_jars_in_bench is Array else 0
		var new_bench_count: int = new_jars_in_bench.size() if new_jars_in_bench is Array else 0
		if new_bench_count != old_bench_count:
			var role := "主台" if key == "master" else "从台"
			events.append("%s舱段 %s%d" % [role, "+" if new_bench_count > old_bench_count else "−", absi(new_bench_count - old_bench_count)])
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
	var warning := _has_warning_event(events)
	_show_feedback("　·　".join(visible_events), Color("e5b85f") if warning else Color("6fd1ae"))

func _has_warning_event(events: Array[String]) -> bool:
	for event in events:
		if "消耗" in event or "冷却" in event or "空置" in event or "故障" in event:
			return true
	return false

func _show_feedback(message: String, tint: Color) -> void:
	_feedback_label.text = message
	_feedback_label.add_theme_color_override("font_color", tint)
	_feedback_label.modulate = Color(1, 1, 1, 1)
	_toggle.modulate = tint
	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_feedback_tween = create_tween()
	_feedback_tween.tween_property(_strip_panel, "modulate", Color.WHITE, 0.35)
	_feedback_tween.parallel().tween_interval(1.8)
	_feedback_tween.tween_property(_feedback_label, "modulate:a", 0.0, 0.65)

func _filled_jar_count(raw_jars: Variant) -> int:
	var count := 0
	if raw_jars is Array:
		for jar in raw_jars:
			if jar is Dictionary and not String(jar.get("liquid", "")).is_empty():
				count += 1
	return count

func _ship_liquid_balances(snapshot: Dictionary) -> Dictionary:
	var inventory: Variant = snapshot.get("shipLiquidInventory", {})
	if not (inventory is Dictionary):
		return {}
	var balances: Variant = inventory.get("balances", {})
	return balances if balances is Dictionary else {}

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
				result.append(str(demand.get("id", "")))
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
	var visible_limit := 24
	for i in mini(raw_jars.size(), visible_limit):
		var jar: Variant = raw_jars[i]
		if jar is Dictionary:
			_resource_jars.add_child(_jar_tile(jar))
	if raw_jars.size() > visible_limit:
		_resource_jars.add_child(UiKit.label("+%d 只未展开" % (raw_jars.size() - visible_limit), UiKit.FONT_SMALL, UiKit.MUTED))

func _jar_tile(jar: Dictionary) -> PanelContainer:
	var shape := String(jar.get("shape", "未知形状"))
	var liquid := String(jar.get("liquid", ""))
	var jar_id: Variant = jar.get("id", null)
	var tint := ShapeVisuals.color_for(shape)
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(78, 82)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1c2633")
	style.border_color = tint
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(5)
	tile.add_theme_stylebox_override("panel", style)
	var content := UiKit.vbox(2)
	tile.add_child(content)
	var head := UiKit.hbox(3)
	var glyph := UiKit.label(ShapeVisuals.glyph_for(shape), 18, tint)
	head.add_child(glyph)
	head.add_child(UiKit.label("Jar", UiKit.FONT_SMALL, UiKit.TEXT))
	if bool(jar.get("isMarked", false)):
		head.add_child(UiKit.label("◆", UiKit.FONT_SMALL, UiKit.WARN))
	content.add_child(head)
	content.add_child(UiKit.label(shape, 10, tint))
	var id_text := "#" + str(jar_id) if jar_id != null else "无编号"
	content.add_child(UiKit.label(id_text, 10, UiKit.MUTED))
	var fill := PanelContainer.new()
	fill.custom_minimum_size = Vector2(0, 7)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = ShapeVisuals.liquid_color_for(liquid) if not liquid.is_empty() else Color("354252")
	fill_style.set_corner_radius_all(3)
	fill.add_theme_stylebox_override("panel", fill_style)
	content.add_child(fill)
	content.add_child(UiKit.label(liquid if not liquid.is_empty() else "空罐", 10, ShapeVisuals.liquid_color_for(liquid) if not liquid.is_empty() else UiKit.MUTED))
	tile.tooltip_text = "%s · %s · %s%s" % [id_text, shape, liquid if not liquid.is_empty() else "空罐", " · 已标记" if bool(jar.get("isMarked", false)) else ""]
	return tile

func _render_resource_liquids(raw_liquids: Variant, liquid_capacity: int) -> void:
	UiKit.clear_children(_resource_liquids)
	var liquid_total := _dictionary_total(raw_liquids)
	var capacity_text := "%d/%d" % [liquid_total, liquid_capacity] if liquid_capacity > 0 else str(liquid_total)
	_resource_liquids.add_child(UiKit.label("飞船液体库存：%s" % capacity_text, UiKit.FONT_SMALL, UiKit.ACCENT))
	if not (raw_liquids is Dictionary) or raw_liquids.is_empty():
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
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color("151d28")
	card_style.border_color = accent
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(7)
	card_style.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", card_style)
	parent.add_child(card)
	var content := UiKit.vbox(4)
	card.add_child(content)
	var header := UiKit.hbox(8)
	content.add_child(header)
	var role_tag := UiKit.label("主台" if role == "主台" else "从台", UiKit.FONT_BODY, accent)
	header.add_child(role_tag)
	header.add_child(UiKit.label(String(workshop.get("name", "")), UiKit.FONT_BODY, UiKit.TEXT))
	header.add_child(UiKit.spacer())
	header.add_child(UiKit.label("Jar %d / %d" % [jars.size(), int(workshop.get("maxJars", 0))], UiKit.FONT_SMALL, accent))
	var marks := UiKit.hbox(6)
	content.add_child(marks)
	for shape in base:
		marks.add_child(_shape_token(String(shape), "基础"))
	for shape in extra:
		marks.add_child(_shape_token(String(shape), "附加"))
	if not jars.is_empty():
		var jar_row := HFlowContainer.new()
		jar_row.add_theme_constant_override("h_separation", 5)
		jar_row.add_theme_constant_override("v_separation", 5)
		content.add_child(jar_row)
		var shown := 0
		for jar in jars:
			if shown >= 12:
				break
			if jar is Dictionary:
				jar_row.add_child(_jar_tile(jar))
				shown += 1
		if jars.size() > shown:
			jar_row.add_child(UiKit.label("+%d 只" % (jars.size() - shown), UiKit.FONT_SMALL, UiKit.MUTED))

	var liquid_row := UiKit.vbox(3)
	content.add_child(liquid_row)
	var liquid_capacity := int(workshop.get("maxLiquids", 0))
	for liquid in liquids:
		var liquid_line := UiKit.hbox(6)
		liquid_row.add_child(liquid_line)
		var amount := int(liquids[liquid])
		var fill_ratio := float(amount) / float(liquid_capacity) if liquid_capacity > 0 else 0.0
		var capacity_tint := UiKit.WARN if fill_ratio >= 0.8 else ShapeVisuals.liquid_color_for(String(liquid))
		var capacity_suffix := " · 满" if fill_ratio >= 1.0 else (" · 接近上限" if fill_ratio >= 0.8 else "")
		var liquid_label := UiKit.label("%s %d / %d%s" % [String(liquid), amount, liquid_capacity, capacity_suffix], UiKit.FONT_SMALL, capacity_tint)
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
			ShapeVisuals.apply_meter_style(meter, capacity_tint)
			liquid_line.add_child(meter)
	var bans: Array = workshop.get("ban", [])
	if not bans.is_empty():
		var ban_names: Array[String] = []
		for ban in bans:
			ban_names.append(String(ban))
		content.add_child(UiKit.label("⚠ 暂存区禁入：%s" % "、".join(ban_names), UiKit.FONT_SMALL, UiKit.WARN))


func _render_order_skill_hud(raw_demands: Variant, raw_sessions: Variant, order_presentation: Dictionary) -> void:
	UiKit.clear_children(_active_order_slots)
	UiKit.clear_children(_passive_order_slots)
	var sessions_by_demand: Dictionary = {}
	if raw_sessions is Array:
		for session in raw_sessions:
			if session is Dictionary and not bool(session.get("isTerminal", false)):
				sessions_by_demand[int(session.get("demandId", -1))] = session
	var active_count := 0
	var passive_count := 0
	if raw_demands is Array:
		for demand in raw_demands:
			if not (demand is Dictionary):
				continue
			var area := String(demand.get("area", ""))
			if area != "Active" and area != "Passive":
				continue
			var demand_id := int(demand.get("id", 0))
			var order_key := String(demand.get("orderDefinitionKey", ""))
			var metadata: Dictionary = order_presentation.get(order_key, {})
			var primary_shape := String(metadata.get("primaryShape", ""))
			var requirements: Array = demand.get("requirements", [])
			var shape_text := _demand_shape_summary(primary_shape, requirements)
			var title := order_key if not order_key.is_empty() else ("主动订单" if area == "Active" else "被动订单")
			var cooling := bool(demand.get("isCoolingDown", false))
			var remaining := int(demand.get("cooldownRemainingLogicalMilli", 0))
			var session: Dictionary = sessions_by_demand.get(demand_id, {})
			var tile := PanelContainer.new()
			var tile_style := StyleBoxFlat.new()
			var accent := ShapeVisuals.color_for(primary_shape) if not primary_shape.is_empty() else (UiKit.ACCENT if area == "Active" else Color("b69af7"))
			if area == "Active":
				tile_style.bg_color = Color("1b2a38")
			else:
				tile_style.bg_color = Color("282238")
			tile_style.border_color = accent
			tile_style.set_border_width_all(1)
			tile_style.set_corner_radius_all(4)
			tile_style.set_content_margin_all(5)
			tile.add_theme_stylebox_override("panel", tile_style)
			tile.custom_minimum_size = Vector2(148, 48) if area == "Active" else Vector2(104, 34)
			var tile_box := UiKit.vbox(1)
			tile.add_child(tile_box)
			var title_row := UiKit.hbox(4)
			tile_box.add_child(title_row)
			var title_label := UiKit.label("%s #%d" % [title.left(13), demand_id], UiKit.FONT_SMALL, accent)
			title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			title_row.add_child(title_label)
			if area == "Active":
				var trigger := UiKit.small_button("启动", 48)
				trigger.disabled = cooling or not session.is_empty()
				trigger.tooltip_text = "请求 Jar Core 启动此主动订单；资源可行性由 Core 最终判定。"
				trigger.pressed.connect(func() -> void: _trigger_active_demand(demand_id))
				title_row.add_child(trigger)
			if not shape_text.is_empty():
				tile_box.add_child(UiKit.label(shape_text, UiKit.FONT_SMALL, ShapeVisuals.color_for(primary_shape) if not primary_shape.is_empty() else UiKit.MUTED))
			var state_text := ""
			var state_color := UiKit.MUTED
			if area == "Active":
				if not session.is_empty():
					state_text = "执行中 · 主%d/从%d" % [int(session.get("completedMasterSteps", 0)), int(session.get("completedSlaveSteps", 0))]
					state_color = UiKit.ACCENT
				elif cooling:
					state_text = "冷却 %.1fs" % (float(remaining) / 1000.0)
					state_color = UiKit.WARN
				else:
					state_text = "就绪"
					state_color = UiKit.OK
			else:
				state_text = "被动槽"
				state_color = Color("b69af7")
			if cooling and area == "Passive":
				state_text = "冷却 %.1fs" % (float(remaining) / 1000.0)
				state_color = UiKit.WARN
			tile_box.add_child(UiKit.label(state_text, UiKit.FONT_SMALL, state_color))
			tile.tooltip_text = "%s · #%d\n%s\n%s" % [area, demand_id, title, shape_text]
			if area == "Active":
				_active_order_slots.add_child(tile)
				active_count += 1
			else:
				_passive_order_slots.add_child(tile)
				passive_count += 1
	if active_count == 0:
		_active_order_slots.add_child(UiKit.label("暂无主动订单", UiKit.FONT_SMALL, UiKit.MUTED))
	if passive_count == 0:
		_passive_order_slots.add_child(UiKit.label("暂无被动订单", UiKit.FONT_SMALL, UiKit.MUTED))

func _trigger_active_demand(demand_id: int) -> void:
	if _host == null or not is_instance_valid(_host) or not _host.has_method("StartActiveDemand"):
		_show_feedback("主动订单入口不可用", UiKit.WARN)
		return
	var raw_result: Variant = _host.call("StartActiveDemand", demand_id)
	if not (raw_result is Dictionary):
		_show_feedback("主动订单没有返回有效结果", UiKit.WARN)
		return
	var result: Dictionary = raw_result
	if bool(result.get("success", false)):
		_show_feedback("主动订单 #%d 已启动" % demand_id, UiKit.OK)
	else:
		var reason := String(result.get("reason", "Core 暂不允许启动"))
		_show_feedback("主动订单 #%d 未启动：%s" % [demand_id, reason], UiKit.WARN)
	_refresh_snapshot()

func _demand_shape_summary(primary_shape: String, requirements: Array) -> String:
	var parts: Array[String] = []
	if not primary_shape.is_empty():
		parts.append("%s 主形" % ShapeVisuals.glyph_for(primary_shape))
	for requirement in requirements:
		if requirement is Dictionary:
			var shape := String(requirement.get("shape", ""))
			if not shape.is_empty():
				parts.append(ShapeVisuals.glyph_for(shape))
	return " ".join(parts)

func _render_demands(raw_demands: Variant, raw_sessions: Variant, order_presentation: Dictionary) -> void:
	UiKit.clear_children(_demands_box)
	var active_group := UiKit.vbox(3)
	var passive_group := UiKit.vbox(3)
	var active_count := 0
	var passive_count := 0
	if raw_demands is Array:
		for demand in raw_demands:
			if not (demand is Dictionary):
				continue
			var area := String(demand.get("area", ""))
			if area != "Active" and area != "Passive":
				continue
			var row := UiKit.hbox(6)
			var cooling := bool(demand.get("isCoolingDown", false))
			var remaining := int(demand.get("cooldownRemainingLogicalMilli", 0))
			var order_key := String(demand.get("orderDefinitionKey", ""))
			var metadata: Dictionary = order_presentation.get(order_key, {})
			var primary_shape := String(metadata.get("primaryShape", ""))
			var title := order_key if not order_key.is_empty() else String(demand.get("type", "订单"))
			row.add_child(UiKit.label("%s  #%d" % [title, int(demand.get("id", 0))], UiKit.FONT_SMALL, ShapeVisuals.color_for(primary_shape) if not primary_shape.is_empty() else UiKit.TEXT))
			if not primary_shape.is_empty():
				row.add_child(_shape_token(primary_shape, "主形"))
			row.add_child(UiKit.label("冷却 %d ms" % remaining if cooling else ("可触发" if area == "Active" else "被动位"), UiKit.FONT_SMALL, UiKit.WARN if cooling else UiKit.MUTED))
			var requirements: Variant = demand.get("requirements", [])
			if requirements is Array:
				for requirement in requirements:
					if requirement is Dictionary:
						row.add_child(_shape_token(String(requirement.get("shape", "")), "液体" if not String(requirement.get("liquid", "")).is_empty() else "空"))
			if area == "Active":
				active_group.add_child(row)
				active_count += 1
			else:
				passive_group.add_child(row)
				passive_count += 1
	_demands_box.add_child(UiKit.label("主动技能 / 主动订单", UiKit.FONT_SMALL, UiKit.ACCENT))
	_demands_box.add_child(active_group)
	if active_count == 0:
		active_group.add_child(UiKit.label("暂无主动订单", UiKit.FONT_SMALL, UiKit.MUTED))
	_demands_box.add_child(UiKit.label("被动技能 / 被动订单", UiKit.FONT_SMALL, Color("b69af7")))
	_demands_box.add_child(passive_group)
	if passive_count == 0:
		passive_group.add_child(UiKit.label("暂无被动订单", UiKit.FONT_SMALL, UiKit.MUTED))
	if raw_sessions is Array:
		for session in raw_sessions:
			if session is Dictionary and not bool(session.get("isTerminal", false)):
				_demands_box.add_child(UiKit.label("执行中 · 订单 #%d · %s · 主台步 %d / 从台步 %d" % [int(session.get("demandId", 0)), String(session.get("stage", "")), int(session.get("completedMasterSteps", 0)), int(session.get("completedSlaveSteps", 0))], UiKit.FONT_SMALL, UiKit.ACCENT))

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
