extends PanelContainer
class_name SpaceHangarAssemblyPreview
## Presentation-only visualization of an authored Hangar selection.
## It does not infer compatibility, slot availability, balance, or runtime behavior.

const FALLBACK_ICONS := {
	"ship": "res://assets/hangar/ship.svg",
	"parser": "res://assets/hangar/parser.svg",
	"workshop": "res://assets/hangar/workshop.svg",
	"device": "res://assets/hangar/device.svg",
	"skill": "res://assets/hangar/skill.svg"
}

var _root: VBoxContainer
var _status: Label
var _ship_stage: Control
var _ship_hull: TextureRect
var _anchor_layer: Control
var _anchor_icons: Array[Dictionary] = []
var _ship_name: Label
var _parser_row: HBoxContainer
var _workshop_row: HBoxContainer
var _device_list: VBoxContainer
var _skill_list: VBoxContainer
var _summary: Label

func _ready() -> void:
	_build_view()
	render({})

func _build_view() -> void:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	add_child(outer)
	_root = outer

	var heading := Label.new()
	heading.text = "ASSEMBLY PREVIEW  /  装配预览"
	heading.add_theme_font_size_override("font_size", 20)
	outer.add_child(heading)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(0.52, 0.84, 0.98, 1.0))
	outer.add_child(_status)

	# The preview uses two columns for the hull and core systems. Skills occupy a
	# separate full-width row; keeping them as a third fixed-width column caused
	# labels and icons to collapse at ordinary game-window widths.
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(layout)

	var ship_panel := PanelContainer.new()
	ship_panel.custom_minimum_size = Vector2(190, 190)
	layout.add_child(ship_panel)
	var ship_box := VBoxContainer.new()
	ship_box.alignment = BoxContainer.ALIGNMENT_CENTER
	ship_box.add_theme_constant_override("separation", 8)
	ship_panel.add_child(ship_box)
	_ship_stage = Control.new()
	_ship_stage.custom_minimum_size = Vector2(150, 122)
	_ship_stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ship_box.add_child(_ship_stage)
	_ship_hull = TextureRect.new()
	_ship_hull.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ship_hull.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ship_hull.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ship_hull.texture = load(String(FALLBACK_ICONS.ship))
	_ship_stage.add_child(_ship_hull)
	_anchor_layer = Control.new()
	_anchor_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_anchor_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ship_stage.add_child(_anchor_layer)
	_ship_stage.resized.connect(_layout_anchor_icons)
	_ship_name = Label.new()
	_ship_name.text = "尚未选择飞船"
	_ship_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ship_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ship_box.add_child(_ship_name)

	var systems_panel := PanelContainer.new()
	systems_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(systems_panel)
	var systems := VBoxContainer.new()
	systems.add_theme_constant_override("separation", 9)
	systems_panel.add_child(systems)
	var systems_heading := Label.new()
	systems_heading.text = "核心系统"
	systems.add_child(systems_heading)
	_parser_row = _make_component_row(systems, "parser", "原石解析器未选择")
	_workshop_row = _make_component_row(systems, "workshop", "工作台组合未选择")
	var device_heading := Label.new()
	device_heading.text = "生产设备槽位"
	systems.add_child(device_heading)
	_device_list = VBoxContainer.new()
	_device_list.add_theme_constant_override("separation", 5)
	systems.add_child(_device_list)

	var skills_panel := PanelContainer.new()
	skills_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(skills_panel)
	var skills := VBoxContainer.new()
	skills.add_theme_constant_override("separation", 8)
	skills_panel.add_child(skills)
	var skills_heading := Label.new()
	skills_heading.text = "技能绑定"
	skills.add_child(skills_heading)
	_skill_list = VBoxContainer.new()
	_skill_list.add_theme_constant_override("separation", 7)
	skills.add_child(_skill_list)

	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_summary)

func _make_component_row(parent: VBoxContainer, category: String, empty_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var icon := _make_icon(category, 48)
	row.add_child(icon)
	var label := Label.new()
	label.text = empty_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row

func _make_icon(category: String, dimension: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(dimension, dimension)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load(String(FALLBACK_ICONS.get(category, FALLBACK_ICONS.ship)))
	return icon

func render(view_model: Dictionary) -> void:
	if not is_instance_valid(_root):
		return
	var inventory: Dictionary = view_model.get("inventory", {})
	var selection: Dictionary = view_model.get("selection", {})
	var ready := bool(view_model.get("isReady", false))
	var ship := _find_ship_choice(
		inventory.get("shipChoices", []),
		String(selection.get("shipId", "")),
		int(selection.get("shipVersion", 0)),
		String(selection.get("shipInstanceId", ""))
	)
	var parser := _find_choice(inventory.get("parserChoices", []), String(selection.get("parserId", "")), int(selection.get("parserVersion", 0)))
	var workshop := _find_choice(inventory.get("workshopChoices", []), String(selection.get("workshopId", "")), int(selection.get("workshopVersion", 0)))

	var hull: Variant = ship.get("hullTexture", null)
	if not (hull is Texture2D):
		hull = ship.get("iconTexture", null)
	if hull is Texture2D:
		_ship_hull.texture = hull
	else:
		_ship_hull.texture = load(String(FALLBACK_ICONS.ship))
	var selected_ship_id := String(selection.get("shipId", "")).strip_edges()
	var selected_ship_version := int(selection.get("shipVersion", 0))
	var selected_ship_instance_id := String(selection.get("shipInstanceId", "")).strip_edges()
	var ship_is_selected := not selected_ship_id.is_empty() and selected_ship_version > 0
	# In owned-inventory mode the instance identity is mandatory. The selection
	# draft validates it before storing; preview asset resolution is presentation
	# only and must not decide whether the player selected a ship.
	if not selected_ship_instance_id.is_empty():
		ship_is_selected = true
	if not ship_is_selected:
		_ship_name.text = "尚未选择飞船"
	elif ship.is_empty():
		_ship_name.text = "%s  [v%d] · 预览资源未解析" % [selected_ship_id, selected_ship_version]
	else:
		_ship_name.text = _choice_label(ship, selected_ship_id)
	_render_ship_anchors(ship, selection, inventory)
	_set_component_row(_parser_row, parser, "parser", "原石解析器未选择")
	_set_component_row(_workshop_row, workshop, "workshop", "工作台组合未选择")
	_render_devices(inventory.get("deviceChoices", []), selection.get("deviceSelections", []))
	_render_skills(inventory.get("skillChoices", []), selection.get("skillSelections", []))

	var selected_device_count := _array_size(selection.get("deviceSelections", []))
	var selected_skill_count := _array_size(selection.get("skillSelections", []))
	var missing: Array[String] = []
	if not ship_is_selected:
		missing.append("飞船")
	if parser.is_empty():
		missing.append("解析器")
	if workshop.is_empty():
		missing.append("工作台组合")
	if float(selection.get("expectedBattleDurationLogicalMilli", 0.0)) <= 0.0:
		missing.append("战斗时长")
	if not ready:
		_status.text = "目录未就绪：当前只展示空状态，不存在可冻结的生产装配"
	elif not missing.is_empty():
		_status.text = "装配尚未完整：缺少 " + "、".join(missing)
	elif bool(view_model.get("canBuild", false)):
		_status.text = "选择结构完整。跨目录兼容性仍由最终装配器检查，预览不提前宣称通过。"
	else:
		_status.text = "选择已展示；等待稳定身份或其他装配前置条件。"
	_summary.text = "设备槽位已选择：%d    技能 / 订单绑定：%d    预计战斗时长：%s 逻辑毫秒" % [
		selected_device_count,
		selected_skill_count,
		str(selection.get("expectedBattleDurationLogicalMilli", 0.0))
	]

func _render_ship_anchors(ship: Dictionary, selection: Dictionary, inventory: Dictionary) -> void:
	for child in _anchor_layer.get_children():
		child.queue_free()
	_anchor_icons.clear()
	if ship.is_empty():
		return
	var anchors: Variant = ship.get("displayAnchors", [])
	if not (anchors is Array):
		return
	var devices: Variant = selection.get("deviceSelections", [])
	for raw_anchor in anchors:
		if not (raw_anchor is Dictionary):
			continue
		var kind := String(raw_anchor.get("componentKind", ""))
		var slot_id := String(raw_anchor.get("logicalSlotId", ""))
		var choice: Dictionary = {}
		if kind == "parser" and slot_id == String(selection.get("parserSlotId", "")):
			choice = _find_choice(inventory.get("parserChoices", []), String(selection.get("parserId", "")), int(selection.get("parserVersion", 0)))
		elif kind == "device" and devices is Array:
			for raw_device in devices:
				if raw_device is Dictionary and String(raw_device.get("slotId", "")) == slot_id:
					choice = _find_choice(inventory.get("deviceChoices", []), String(raw_device.get("definitionId", "")), int(raw_device.get("definitionVersion", 0)))
					break
		if choice.is_empty():
			continue
		var icon := TextureRect.new()
		var base_size := 34.0 * float(raw_anchor.get("iconScale", 1.0))
		icon.custom_minimum_size = Vector2(base_size, base_size)
		icon.size = icon.custom_minimum_size
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_set_icon(icon, choice.get("iconTexture"), kind)
		icon.tooltip_text = "%s · %s" % [slot_id, _choice_label(choice, "")]
		_anchor_layer.add_child(icon)
		_anchor_icons.append({"control": icon, "position": raw_anchor.get("normalizedPosition", Vector2(0.5, 0.5)), "rotation": float(raw_anchor.get("rotationDegrees", 0.0))})
	_layout_anchor_icons()

func _layout_anchor_icons() -> void:
	if not is_instance_valid(_anchor_layer):
		return
	for entry in _anchor_icons:
		var icon: TextureRect = entry.get("control")
		if not is_instance_valid(icon):
			continue
		var normalized: Variant = entry.get("position", Vector2(0.5, 0.5))
		if not (normalized is Vector2):
			continue
		icon.position = Vector2(normalized.x * _ship_stage.size.x - icon.size.x * 0.5, normalized.y * _ship_stage.size.y - icon.size.y * 0.5)
		icon.rotation_degrees = float(entry.get("rotation", 0.0))
func _set_component_row(row: HBoxContainer, choice: Dictionary, category: String, empty_text: String) -> void:
	var icon := row.get_child(0) as TextureRect
	var label := row.get_child(1) as Label
	_set_icon(icon, choice.get("iconTexture"), category)
	label.text = _choice_label(choice, empty_text)

func _render_devices(device_choices: Variant, selected_devices: Variant) -> void:
	_clear_children(_device_list)
	if not (selected_devices is Array) or selected_devices.is_empty():
		var available_count := _array_size(device_choices)
		_add_empty_label(_device_list, "当前没有可安装的生产设备定义" if available_count == 0 else "尚未安装生产设备")
		return
	for raw_selection in selected_devices:
		if not (raw_selection is Dictionary):
			continue
		var choice := _find_choice(device_choices, String(raw_selection.get("definitionId", "")), int(raw_selection.get("definitionVersion", 0)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		_device_list.add_child(row)
		var icon := _make_icon("device", 38)
		_set_icon(icon, choice.get("iconTexture"), "device")
		row.add_child(icon)
		var label := Label.new()
		label.text = "%s  →  %s" % [String(raw_selection.get("slotId", "未命名槽位")), _choice_label(choice, "目录定义不可用")]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

func _render_skills(skill_choices: Variant, selected_skills: Variant) -> void:
	_clear_children(_skill_list)
	if not (selected_skills is Array) or selected_skills.is_empty():
		_add_empty_label(_skill_list, "尚未绑定技能")
		return
	for raw_selection in selected_skills:
		if not (raw_selection is Dictionary):
			continue
		var choice := _find_choice(skill_choices, String(raw_selection.get("skillId", "")), int(raw_selection.get("definitionVersion", 0)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_skill_list.add_child(row)
		var icon := _make_icon("skill", 38)
		_set_icon(icon, choice.get("iconTexture"), "skill")
		row.add_child(icon)
		var label := Label.new()
		label.text = "%s\n%s · %s" % [
			_choice_label(choice, "技能定义不可用"),
			String(raw_selection.get("orderDefinitionKey", "订单未指定")),
			String(raw_selection.get("controlArea", "控制区域未指定"))
		]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

func _find_ship_choice(raw_choices: Variant, definition_id: String, version: int, instance_id: String) -> Dictionary:
	if not (raw_choices is Array):
		return {}
	# Owned ship instances are the selectable unit. Prefer their stable instance
	# identity so a stale/missing definition projection cannot falsely show
	# "尚未选择飞船" after the picker has selected an owned ship.
	if not instance_id.is_empty():
		for raw_choice in raw_choices:
			if raw_choice is Dictionary and String(raw_choice.get("instanceId", "")) == instance_id:
				return raw_choice
	if definition_id.is_empty() or version <= 0:
		return {}
	return _find_choice(raw_choices, definition_id, version)

func _find_choice(raw_choices: Variant, definition_id: String, version: int) -> Dictionary:
	if definition_id.is_empty() or version <= 0 or not (raw_choices is Array):
		return {}
	for raw_choice in raw_choices:
		if raw_choice is Dictionary and String(raw_choice.get("id", "")) == definition_id and int(raw_choice.get("version", 0)) == version:
			return raw_choice
	return {}

func _choice_label(choice: Dictionary, empty_text: String) -> String:
	if choice.is_empty():
		return empty_text
	return "%s  [v%d]" % [String(choice.get("label", choice.get("id", "未命名定义"))), int(choice.get("version", 0))]

func _set_icon(icon: TextureRect, raw_texture: Variant, category: String) -> void:
	if raw_texture is Texture2D:
		icon.texture = raw_texture
	else:
		icon.texture = load(String(FALLBACK_ICONS.get(category, FALLBACK_ICONS.ship)))

func _add_empty_label(parent: VBoxContainer, text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)

func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()

func _array_size(value: Variant) -> int:
	return value.size() if value is Array else 0
