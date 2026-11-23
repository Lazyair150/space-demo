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
var _ship_icon: TextureRect
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

	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 18)
	outer.add_child(layout)

	var ship_panel := PanelContainer.new()
	ship_panel.custom_minimum_size = Vector2(190, 190)
	layout.add_child(ship_panel)
	var ship_box := VBoxContainer.new()
	ship_box.alignment = BoxContainer.ALIGNMENT_CENTER
	ship_box.add_theme_constant_override("separation", 8)
	ship_panel.add_child(ship_box)
	_ship_icon = _make_icon("ship", 116)
	_ship_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ship_box.add_child(_ship_icon)
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
	skills_panel.custom_minimum_size.x = 190
	layout.add_child(skills_panel)
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
	var ship := _find_choice(inventory.get("shipChoices", []), String(selection.get("shipId", "")), int(selection.get("shipVersion", 0)))
	var parser := _find_choice(inventory.get("parserChoices", []), String(selection.get("parserId", "")), int(selection.get("parserVersion", 0)))
	var workshop := _find_choice(inventory.get("workshopChoices", []), String(selection.get("workshopId", "")), int(selection.get("workshopVersion", 0)))

	_set_icon(_ship_icon, ship.get("iconTexture"), "ship")
	_ship_name.text = _choice_label(ship, "尚未选择飞船")
	_set_component_row(_parser_row, parser, "parser", "原石解析器未选择")
	_set_component_row(_workshop_row, workshop, "workshop", "工作台组合未选择")
	_render_devices(inventory.get("deviceChoices", []), selection.get("deviceSelections", []))
	_render_skills(inventory.get("skillChoices", []), selection.get("skillSelections", []))

	var selected_device_count := _array_size(selection.get("deviceSelections", []))
	var selected_skill_count := _array_size(selection.get("skillSelections", []))
	var missing: Array[String] = []
	if ship.is_empty():
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

func _set_component_row(row: HBoxContainer, choice: Dictionary, category: String, empty_text: String) -> void:
	var icon := row.get_child(0) as TextureRect
	var label := row.get_child(1) as Label
	_set_icon(icon, choice.get("iconTexture"), category)
	label.text = _choice_label(choice, empty_text)

func _render_devices(device_choices: Variant, selected_devices: Variant) -> void:
	_clear_children(_device_list)
	if not (selected_devices is Array) or selected_devices.is_empty():
		_add_empty_label(_device_list, "尚未安装生产设备")
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
