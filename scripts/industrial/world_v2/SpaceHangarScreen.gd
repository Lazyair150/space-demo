extends Control
class_name SpaceHangarScreen
## Standalone Hangar UI. It presents only authored inventory and delegates all domain
## validation/build decisions to SpaceHangarSelectionController + Preparation.

@export var loadout_identity: Dictionary = {}

var _preparation: SpaceHangarPreparation
var _controller: SpaceHangarSelectionController
var _ship_picker: OptionButton
var _parser_picker: OptionButton
var _workshop_picker: OptionButton
var _duration_picker: SpinBox
var _build_button: Button
var _status_label: Label
var _inventory_label: Label
var _refresh_button: Button
var _suppress_picker_events: bool = false

func _ready() -> void:
	_preparation = get_node_or_null("Preparation") as SpaceHangarPreparation
	_controller = SpaceHangarSelectionController.new()
	_build_interface()
	_controller.view_model_changed.connect(_on_view_model_changed)
	var ready := _controller.configure(_preparation, loadout_identity)
	_render_view_model(_controller.get_view_model())
	if not ready:
		_status_label.text = "机库目录尚未就绪：请在编辑器中为 Preparation 配置有效的目录资源包。"

func _build_interface() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.055, 0.075, 0.12, 1.0)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_right", 42)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	var title := Label.new()
	title.text = "SPACE HANGAR  /  战前装配"
	title.add_theme_font_size_override("font_size", 30)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "选择只引用目录中真实存在的定义版本；最终兼容性与冻结由装配器负责。"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(subtitle)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.42, 1.0))
	root.add_child(_status_label)

	var selection_panel := PanelContainer.new()
	root.add_child(selection_panel)
	var selection_box := VBoxContainer.new()
	selection_box.add_theme_constant_override("separation", 10)
	selection_panel.add_child(selection_box)

	_add_section_title(selection_box, "核心配置")
	_ship_picker = _add_picker(selection_box, "飞船定义")
	_parser_picker = _add_picker(selection_box, "原石解析器")
	_workshop_picker = _add_picker(selection_box, "工作台组合")

	var duration_row := HBoxContainer.new()
	selection_box.add_child(duration_row)
	var duration_label := Label.new()
	duration_label.text = "预计战斗时长（逻辑毫秒）"
	duration_label.custom_minimum_size.x = 250
	duration_row.add_child(duration_label)
	_duration_picker = SpinBox.new()
	_duration_picker.min_value = 0.0
	_duration_picker.max_value = 1000000000.0
	_duration_picker.step = 1000.0
	_duration_picker.value = 0.0
	_duration_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duration_row.add_child(_duration_picker)
	_duration_picker.value_changed.connect(_on_duration_changed)

	var inventory_panel := PanelContainer.new()
	root.add_child(inventory_panel)
	var inventory_box := VBoxContainer.new()
	inventory_panel.add_child(inventory_box)
	_add_section_title(inventory_box, "目录库存")
	_inventory_label = Label.new()
	_inventory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory_box.add_child(_inventory_label)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)
	_refresh_button = Button.new()
	_refresh_button.text = "重新读取目录"
	footer.add_child(_refresh_button)
	_refresh_button.pressed.connect(_on_refresh_pressed)
	_build_button = Button.new()
	_build_button.text = "检查并冻结装配快照"
	_build_button.disabled = true
	footer.add_child(_build_button)
	_build_button.pressed.connect(_on_build_pressed)

	_ship_picker.item_selected.connect(_on_ship_selected)
	_parser_picker.item_selected.connect(_on_parser_selected)
	_workshop_picker.item_selected.connect(_on_workshop_selected)

func _add_section_title(parent: VBoxContainer, text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 20)
	parent.add_child(label)

func _add_picker(parent: VBoxContainer, caption: String) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 250
	row.add_child(label)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_item("目录未加载")
	picker.set_item_disabled(0, true)
	row.add_child(picker)
	return picker

func _on_view_model_changed(view_model: Dictionary) -> void:
	_render_view_model(view_model)

func _render_view_model(view_model: Dictionary) -> void:
	if not is_instance_valid(_status_label):
		return
	var inventory: Dictionary = view_model.get("inventory", {})
	var ready := bool(view_model.get("isReady", false))
	_suppress_picker_events = true
	_fill_picker(_ship_picker, inventory.get("shipChoices", []), "没有可用飞船定义")
	_fill_picker(_parser_picker, inventory.get("parserChoices", []), "没有可用解析器定义")
	_fill_picker(_workshop_picker, inventory.get("workshopChoices", []), "没有可用工作台组合")
	var selection: Dictionary = view_model.get("selection", {})
	_select_exact(_ship_picker, String(selection.get("shipId", "")), int(selection.get("shipVersion", 0)))
	_select_exact(_parser_picker, String(selection.get("parserId", "")), int(selection.get("parserVersion", 0)))
	_select_exact(_workshop_picker, String(selection.get("workshopId", "")), int(selection.get("workshopVersion", 0)))
	_suppress_picker_events = false

	var devices: Array = inventory.get("deviceChoices", [])
	var skills: Array = inventory.get("skillChoices", [])
	var effects: Array = inventory.get("effectChoices", [])
	_inventory_label.text = "飞船：%d    解析器：%d    工作台组合：%d\n生产设备：%d    技能：%d    效果定义：%d" % [
		_array_size(inventory.get("shipChoices", [])),
		_array_size(inventory.get("parserChoices", [])),
		_array_size(inventory.get("workshopChoices", [])),
		devices.size(), skills.size(), effects.size()
	]
	if not ready:
		_status_label.text = String(inventory.get("unavailableReason", view_model.get("lastError", "目录不可用")))
	elif not _identity_is_supplied():
		_status_label.text = "目录已加载。等待所属游戏流程提供 shipWorldId / loadoutId / loadoutVersion。"
	elif not devices.is_empty() or not skills.is_empty():
		_status_label.text = "目录包含生产设备或技能定义；当前界面尚未提供这些槽位的完整绑定控件，因此冻结操作保持关闭。"
	else:
		_status_label.text = "目录已就绪。选择飞船、解析器、工作台组合并填写预计战斗时长。"
	_update_build_enabled(view_model)

func _fill_picker(picker: OptionButton, raw_choices: Variant, empty_text: String) -> void:
	picker.clear()
	picker.add_item(empty_text)
	picker.set_item_disabled(0, true)
	if not (raw_choices is Array):
		return
	for choice in raw_choices:
		if not (choice is Dictionary):
			continue
		var definition_id := String(choice.get("id", ""))
		var version := int(choice.get("version", 0))
		if definition_id.is_empty() or version <= 0:
			continue
		var label := String(choice.get("label", definition_id))
		picker.add_item("%s  [v%d]" % [label, version])
		picker.set_item_metadata(picker.item_count - 1, {
			"id": definition_id,
			"version": version
		})

func _select_exact(picker: OptionButton, definition_id: String, version: int) -> void:
	if definition_id.is_empty() or version <= 0:
		return
	for index in range(1, picker.item_count):
		var metadata: Dictionary = picker.get_item_metadata(index)
		if String(metadata.get("id", "")) == definition_id and int(metadata.get("version", 0)) == version:
			picker.select(index)
			return

func _on_ship_selected(index: int) -> void:
	if _suppress_picker_events:
		return
	var choice: Dictionary = _ship_picker.get_item_metadata(index)
	_controller.set_ship(String(choice.get("id", "")), int(choice.get("version", 0)))

func _on_parser_selected(index: int) -> void:
	if _suppress_picker_events:
		return
	var choice: Dictionary = _parser_picker.get_item_metadata(index)
	_controller.set_parser(String(choice.get("id", "")), int(choice.get("version", 0)), "ore-parser")

func _on_workshop_selected(index: int) -> void:
	if _suppress_picker_events:
		return
	var choice: Dictionary = _workshop_picker.get_item_metadata(index)
	_controller.set_workshop(String(choice.get("id", "")), int(choice.get("version", 0)))

func _on_duration_changed(value: float) -> void:
	if value > 0.0:
		_controller.set_expected_battle_duration(value)
	else:
		_update_build_enabled(_controller.get_view_model())

func _on_refresh_pressed() -> void:
	_controller.refresh_inventory()

func _on_build_pressed() -> void:
	var snapshot := _controller.build_loadout_snapshot()
	if snapshot == null:
		_status_label.text = String(_controller.get_view_model().get("lastError", "装配快照构建失败"))
		return
	_status_label.text = "装配快照已冻结：%s" % snapshot.loadout_fingerprint()

func _update_build_enabled(view_model: Dictionary) -> void:
	if not is_instance_valid(_build_button):
		return
	var inventory: Dictionary = view_model.get("inventory", {})
	var advanced_choices_exist := (
		_array_size(inventory.get("deviceChoices", [])) > 0
		or _array_size(inventory.get("skillChoices", [])) > 0
	)
	_build_button.disabled = (
		not bool(view_model.get("canBuild", false))
		or _duration_picker.value <= 0.0
		or advanced_choices_exist
	)

func _identity_is_supplied() -> bool:
	return (
		String(loadout_identity.get("shipWorldId", "")).strip_edges() != ""
		and String(loadout_identity.get("loadoutId", "")).strip_edges() != ""
		and int(loadout_identity.get("loadoutVersion", 0)) > 0
	)

func _array_size(value: Variant) -> int:
	return value.size() if value is Array else 0
