extends Control
class_name SpaceHangarScreen
## Standalone visual Hangar. Authored definitions own their optional sprites;
## this screen supplies category SVG fallbacks and delegates all domain decisions.

@export var loadout_identity: Dictionary = {}
@export var board_definition: SpaceHangarBoardDefinition
@export var parser_slot_id: String = ""
## Slot identifiers are supplied by the owning ship/loadout flow, never inferred from device types.
@export var device_slot_ids: PackedStringArray = PackedStringArray()
## Each entry is authored by the owning order flow: { "orderDefinitionKey": "...", "label": "..." }.
@export var skill_order_bindings: Array[Dictionary] = []
@export var stage_catalog: SpaceStageCatalog
@export var campaign_id: String = "rift_frontier"

const ShapeVisuals := preload("res://scripts/industrial/ui/ShapeVisuals.gd")

const FALLBACK_ICONS := {
	"ship": "res://assets/hangar/ship.svg",
	"parser": "res://assets/hangar/parser.svg",
	"workshop": "res://assets/hangar/workshop.svg",
	"device": "res://assets/hangar/device.svg",
	"skill": "res://assets/hangar/skill.svg",
	"effect": "res://assets/hangar/effect.svg"
}

var _preparation: SpaceHangarPreparation
var _controller: SpaceHangarSelectionController
var _ship_picker: OptionButton
var _parser_picker: OptionButton
var _workshop_picker: OptionButton
var _master_workshop_picker: OptionButton
var _slave_workshop_picker: OptionButton
var _duration_picker: SpinBox
var _build_button: Button
var _status_label: Label
var _inventory_label: Label
var _assembly_preview: SpaceHangarAssemblyPreview
var _refresh_confirmation: ConfirmationDialog
var _device_section: VBoxContainer
var _skill_section: VBoxContainer
var _effect_section: VBoxContainer
var _board_slot_section: VBoxContainer
var _board_slot_pickers: Dictionary = {}
var _stage_picker: OptionButton
var _stage_info_label: Label
var _selected_stage: SpaceStageDefinition
var _device_pickers: Dictionary = {}
var _pending_skill_choices: Dictionary = {}
var _primary_icons: Dictionary = {}
var _suppress_picker_events: bool = false
var _board_configuration_valid: bool = true
var _master_workshop_slot_id: String = "workshop.master"
var _slave_workshop_slot_id: String = "workshop.slave"

func _ready() -> void:
	GameFlow.enter_screen(GameFlow.Screen.HANGAR)
	_preparation = get_node_or_null("Preparation") as SpaceHangarPreparation
	_apply_board_definition()
	_controller = SpaceHangarSelectionController.new()
	if _preparation != null:
		# Run the idempotent demo-save migration on every Hangar entry. Older local
		# saves may already have progression data but lack the mandatory starter ship.
		if not SpaceDemoProgressionBootstrap.ensure_starting_inventory(_preparation.catalog_bundle_resource):
			push_error("[Hangar] Demo starting inventory migration failed; owned ship inventory may be incomplete.")
		_preparation.player_progression_state = GameState.space_progression_state
	GameState.space_progression_state_changed.connect(_on_progression_state_changed)
	GameState.space_campaign_progress_changed.connect(_on_campaign_progress_changed)
	_build_interface()
	_controller.view_model_changed.connect(_on_view_model_changed)
	var ready := _controller.configure(_preparation, loadout_identity, board_definition)
	if ready:
		_controller.set_expected_battle_duration(_duration_picker.value)
	_render_view_model(_controller.get_view_model())
	if not ready:
		_status_label.text = "机库目录尚未就绪：请在编辑器中为 Preparation 配置有效的目录资源包。"

func _apply_board_definition() -> void:
	if board_definition == null:
		return # Explicit legacy scene configuration remains supported during migration.
	var errors := board_definition.get_validation_errors()
	if not errors.is_empty():
		_board_configuration_valid = false
		push_error("Hangar board definition rejected: " + "; ".join(errors))
		return
	var projection_errors := board_definition.get_runtime_projection_errors()
	if not projection_errors.is_empty():
		_board_configuration_valid = false
		push_error("Hangar board exceeds the current runtime slot projection: " + "; ".join(projection_errors))
		return
	var configuration := board_definition.build_hangar_configuration()
	if configuration.is_empty():
		_board_configuration_valid = false
		return
	_board_configuration_valid = true
	parser_slot_id = String(configuration.get("parserSlotId", ""))
	device_slot_ids = PackedStringArray(configuration.get("deviceSlotIds", PackedStringArray()))
	skill_order_bindings.clear()
	for raw_binding in configuration.get("skillOrderBindings", []):
		if raw_binding is Dictionary:
			skill_order_bindings.append(raw_binding.duplicate(true))
	_master_workshop_slot_id = String(configuration.get("masterWorkshopSlotId", ""))
	_slave_workshop_slot_id = String(configuration.get("slaveWorkshopSlotId", ""))

func _build_interface() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.035, 0.055, 0.09, 1.0)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The hangar is a responsive vertical page. A horizontal scrollbar here
	# indicates a broken child minimum-width constraint, not intended navigation.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_theme_constant_override("separation", 14)
	scroll.add_child(root)

	var title := Label.new()
	title.text = "SPACE HANGAR  /  战前装配"
	title.add_theme_font_size_override("font_size", 30)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "把拥有的独立元件安装到工作区位置；定义描述规则，实例保存成长，槽位决定当前角色。"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(subtitle)
	_build_stage_section(root)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.42, 1.0))
	root.add_child(_status_label)

	_assembly_preview = SpaceHangarAssemblyPreview.new()
	_assembly_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_assembly_preview)

	var selection_panel := PanelContainer.new()
	root.add_child(selection_panel)
	var selection_box := VBoxContainer.new()
	selection_box.add_theme_constant_override("separation", 12)
	selection_panel.add_child(selection_box)
	_add_section_title(selection_box, "核心配置")
	_ship_picker = _add_picker(selection_box, "飞船定义", "ship")
	_parser_picker = _add_picker(selection_box, "分解区 · 原石解析器槽位", "parser")
	_workshop_picker = _add_picker(selection_box, "工作区规则配置", "workshop")
	_master_workshop_picker = _add_picker(selection_box, "工作区 · 主台位置", "workshop")
	_slave_workshop_picker = _add_picker(selection_box, "工作区 · 从台位置", "workshop")

	_board_slot_section = VBoxContainer.new()
	_board_slot_section.add_theme_constant_override("separation", 10)
	selection_box.add_child(_board_slot_section)

	_device_section = VBoxContainer.new()
	_device_section.add_theme_constant_override("separation", 8)
	selection_box.add_child(_device_section)
	_skill_section = VBoxContainer.new()
	_skill_section.add_theme_constant_override("separation", 8)
	selection_box.add_child(_skill_section)

	var duration_row := HBoxContainer.new()
	selection_box.add_child(duration_row)
	var duration_label := Label.new()
	duration_label.text = "预计战斗时长（逻辑毫秒）"
	duration_label.custom_minimum_size.x = 250
	duration_row.add_child(duration_label)
	_duration_picker = SpinBox.new()
	_duration_picker.min_value = 1000.0
	_duration_picker.max_value = 1000000000.0
	_duration_picker.step = 1000.0
	_duration_picker.value = 60000.0
	_duration_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duration_row.add_child(_duration_picker)
	_duration_picker.value_changed.connect(_on_duration_changed)

	var inventory_panel := PanelContainer.new()
	root.add_child(inventory_panel)
	var inventory_box := VBoxContainer.new()
	inventory_box.add_theme_constant_override("separation", 10)
	inventory_panel.add_child(inventory_box)
	_add_section_title(inventory_box, "目录库存")
	_inventory_label = Label.new()
	_inventory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory_box.add_child(_inventory_label)
	_effect_section = VBoxContainer.new()
	_effect_section.add_theme_constant_override("separation", 6)
	inventory_box.add_child(_effect_section)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)
	var refresh_button := Button.new()
	refresh_button.text = "重新读取目录"
	footer.add_child(refresh_button)
	refresh_button.pressed.connect(_on_refresh_pressed)
	_refresh_confirmation = ConfirmationDialog.new()
	_refresh_confirmation.dialog_text = "重新读取目录会丢弃当前未冻结的选择草稿。是否继续？"
	add_child(_refresh_confirmation)
	_refresh_confirmation.confirmed.connect(_on_refresh_confirmed)
	_build_button = Button.new()
	_build_button.text = "装配并进入战斗"
	_build_button.disabled = true
	footer.add_child(_build_button)
	_build_button.pressed.connect(_on_build_pressed)

	if board_definition != null:
		_parser_picker.visible = false
		_master_workshop_picker.visible = false
		_slave_workshop_picker.visible = false
		_device_section.visible = false
		_skill_section.visible = false

	_ship_picker.item_selected.connect(_on_ship_selected)
	_parser_picker.item_selected.connect(_on_parser_selected)
	_workshop_picker.item_selected.connect(_on_workshop_selected)
	_master_workshop_picker.item_selected.connect(_on_master_workshop_selected)
	_slave_workshop_picker.item_selected.connect(_on_slave_workshop_selected)

func _build_stage_section(root: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	root.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	_add_section_title(content, "战役关卡")
	_stage_picker = OptionButton.new()
	_stage_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_stage_picker)
	_stage_info_label = Label.new()
	_stage_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_stage_info_label)
	_stage_picker.item_selected.connect(_on_stage_selected)
	_refresh_stage_picker()

func _refresh_stage_picker() -> void:
	if not is_instance_valid(_stage_picker):
		return
	_stage_picker.clear()
	_selected_stage = null
	if stage_catalog == null or not stage_catalog.get_validation_errors().is_empty():
		_stage_picker.add_item("战役目录未配置")
		_stage_picker.set_item_disabled(0, true)
		_stage_info_label.text = "关卡数据不可用；请为 Hangar 配置版本化的 SpaceStageCatalog。"
		return
	_stage_picker.add_item("自由战斗 · 无关卡目标")
	_stage_picker.set_item_metadata(0, {})
	_stage_picker.select(0)
	_stage_info_label.text = "自由战斗：保留无尽战斗循环，不启用有限关卡结算。"
	var cleared: Array = []
	if GameState.space_campaign_progress_state != null:
		cleared = GameState.space_campaign_progress_state.cleared_stage_keys()
	var stages := stage_catalog.stages_for_campaign(campaign_id)
	for stage in stages:
		var unlocked := stage_catalog.is_unlocked(stage, cleared)
		var prefix := "" if unlocked else "🔒 "
		_stage_picker.add_item("%s%02d · %s" % [prefix, stage.sequence_index, stage.display_name])
		var item_index := _stage_picker.item_count - 1
		_stage_picker.set_item_metadata(item_index, {"stageId": String(stage.stage_id), "version": stage.definition_version})
		if not unlocked:
			_stage_picker.set_item_disabled(item_index, true)
	if stages.is_empty():
		_stage_info_label.text += "\\n当前战役没有可挑战关卡。"


func _on_stage_selected(index: int) -> void:
	_selected_stage = null
	if stage_catalog == null or index < 0 or index >= _stage_picker.item_count:
		return
	var metadata: Variant = _stage_picker.get_item_metadata(index)
	if not (metadata is Dictionary):
		return
	if metadata.is_empty():
		_stage_info_label.text = "自由战斗：不启用有限关卡目标与结算。"
		return
	_selected_stage = stage_catalog.resolve_stage(String(metadata.get("stageId", "")), int(metadata.get("version", 0)))
	if _selected_stage == null:
		_stage_info_label.text = "所选关卡的精确版本无法解析。"
		return
	var objective_labels := {
		"eliminate_all": "歼灭全部敌机",
		"survive_duration": "坚持指定时间",
		"collect_resource": "收集指定资源",
		"protect_target": "保护目标",
		"boss": "击败首领"
	}
	_stage_info_label.text = "%s\n目标：%s   推荐装配等级：%d   预计时长：%d 分钟\n%s\n奖励预览：%s" % [
		_selected_stage.display_name,
		String(objective_labels.get(_selected_stage.objective, _selected_stage.objective)),
		_selected_stage.recommended_loadout_level,
		_selected_stage.estimated_minutes,
		_selected_stage.briefing,
		JSON.stringify(_selected_stage.completion_rewards)
	]

func get_selected_stage() -> SpaceStageDefinition:
	return _selected_stage

func _on_campaign_progress_changed(_state: SpaceCampaignProgressState) -> void:
	_refresh_stage_picker()

func _add_section_title(parent: VBoxContainer, text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 19)
	parent.add_child(label)

func _add_picker(parent: VBoxContainer, caption: String, category: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var icon := _make_icon(category, 58)
	row.add_child(icon)
	_primary_icons[category] = icon
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 160
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_item("目录未加载")
	picker.set_item_disabled(0, true)
	row.add_child(picker)
	return picker

func _make_icon(category: String, dimension: int = 52) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(dimension, dimension)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load(String(FALLBACK_ICONS.get(category, FALLBACK_ICONS.effect)))
	return icon

func _set_icon_texture(icon: TextureRect, raw_texture: Variant, category: String) -> void:
	if raw_texture is Texture2D:
		icon.texture = raw_texture
	else:
		icon.texture = load(String(FALLBACK_ICONS.get(category, FALLBACK_ICONS.effect)))

func _on_view_model_changed(view_model: Dictionary) -> void:
	_render_view_model(view_model)

func _render_view_model(view_model: Dictionary) -> void:
	if not is_instance_valid(_status_label):
		return
	var inventory: Dictionary = view_model.get("inventory", {})
	var ready := bool(view_model.get("isReady", false))
	_assembly_preview.render(view_model)
	var selectable_inventory: Dictionary = inventory if ready else {}
	var selection: Dictionary = view_model.get("selection", {})
	_suppress_picker_events = true
	_fill_picker(_ship_picker, selectable_inventory.get("shipChoices", []), "没有可用飞船定义", "ship")
	_fill_picker(_parser_picker, selectable_inventory.get("parserChoices", []), "没有可用解析器定义", "parser")
	_fill_picker(_workshop_picker, selectable_inventory.get("workshopWorldChoices", selectable_inventory.get("workshopChoices", [])), "没有可用工作区规则配置", "workshop")
	var selected_world_key := String(selection.get("workshopId", "")) + "@" + str(int(selection.get("workshopVersion", 0)))
	var compatible_workshop_instances: Array = []
	for choice in selectable_inventory.get("workshopInstanceChoices", []):
		if choice is Dictionary and (selected_world_key == "@" or selected_world_key.ends_with("@0") or choice.get("compatibleWorldKeys", []).has(selected_world_key)):
			compatible_workshop_instances.append(choice)
	_fill_picker(_master_workshop_picker, compatible_workshop_instances, "主台位置未安装兼容元件", "workshop")
	_fill_picker(_slave_workshop_picker, compatible_workshop_instances, "从台位置未安装兼容元件", "workshop")
	_select_exact(_ship_picker, String(selection.get("shipId", "")), int(selection.get("shipVersion", 0)), String(selection.get("shipInstanceId", "")))
	_select_exact(_parser_picker, String(selection.get("parserId", "")), int(selection.get("parserVersion", 0)), String(selection.get("parserInstanceId", "")))
	_select_exact(_workshop_picker, String(selection.get("workshopId", "")), int(selection.get("workshopVersion", 0)))
	_select_instance(_master_workshop_picker, String(selection.get("masterWorkshopInstanceId", "")))
	_select_instance(_slave_workshop_picker, String(selection.get("slaveWorkshopInstanceId", "")))
	_set_icon_for_selection(_primary_icons.ship, _ship_picker, "ship")
	_set_icon_for_selection(_primary_icons.parser, _parser_picker, "parser")
	_set_icon_for_selection(_primary_icons.workshop, _master_workshop_picker, "workshop")
	_suppress_picker_events = false

	_rebuild_board_slot_section(selectable_inventory, selection)
	_rebuild_device_section(selectable_inventory.get("deviceChoices", []), selection.get("deviceSelections", []))
	_rebuild_skill_section(selectable_inventory.get("skillChoices", []), selection.get("skillSelections", []))
	_rebuild_effect_section(selectable_inventory.get("effectChoices", []))

	var devices: Array = inventory.get("deviceChoices", [])
	var skills: Array = inventory.get("skillChoices", [])
	var effects: Array = inventory.get("effectChoices", [])
	_inventory_label.text = "飞船：%d    解析器：%d    工作区规则：%d\n生产设备：%d    技能：%d    效果定义：%d" % [
		_array_size(inventory.get("shipChoices", [])),
		_array_size(inventory.get("parserChoices", [])),
		_array_size(inventory.get("workshopWorldChoices", inventory.get("workshopChoices", []))),
		devices.size(), skills.size(), effects.size()
	]
	if not ready:
		_status_label.text = String(inventory.get("unavailableReason", view_model.get("lastError", "目录不可用")))
	elif _preparation != null and _preparation.player_progression_state == null:
		_status_label.text = "玩家成长存档尚未注入 Preparation；当前不能使用生产机库实例库存。"
	elif not _identity_is_supplied():
		_status_label.text = "目录已加载。等待所属游戏流程提供 shipWorldId / loadoutId / loadoutVersion。"
	elif not String(view_model.get("lastError", "")).is_empty():
		_status_label.text = String(view_model.get("lastError", ""))
	elif board_definition != null and not _controller.validate_assignments().is_empty():
		_status_label.text = "电路板尚未完成安装： " + "; ".join(_controller.validate_assignments())
	elif parser_slot_id.strip_edges().is_empty():
		_status_label.text = "等待游戏流程提供 parser_slot_id；机库不会自行创建解析器槽位身份。"
	elif not _slot_configuration_is_valid():
		_status_label.text = "机库槽位配置无效：设备槽位必须唯一且不能占用解析器槽位，技能订单键必须唯一。"
	elif not devices.is_empty() and device_slot_ids.is_empty():
		_status_label.text = "目录含生产设备，但游戏流程尚未提供 device_slot_ids；请先配置真实设备槽位。"
	elif not skills.is_empty() and skill_order_bindings.is_empty():
		_status_label.text = "目录含技能，但游戏流程尚未提供 skill_order_bindings；请先配置真实订单绑定键。"
	else:
		_status_label.text = "目录已就绪。选择项目时会保留定义版本；最终兼容性由装配器裁定。"
	_update_build_enabled(view_model)

func _fill_picker(picker: OptionButton, raw_choices: Variant, empty_text: String, category: String) -> void:
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
		var instance_suffix := " · Lv%d · %s" % [int(choice.get("level", 1)), String(choice.get("instanceId", ""))] if choice.has("instanceId") else " · 主台 Lv%d / 从台 Lv%d" % [int(choice.get("masterLevel", 1)), int(choice.get("slaveLevel", 1))] if choice.has("masterInstanceId") else ""
		var label := String(choice.get("label", definition_id)) + instance_suffix
		var icon_texture: Variant = choice.get("iconTexture")
		if not (icon_texture is Texture2D):
			icon_texture = load(String(FALLBACK_ICONS.get(category, FALLBACK_ICONS.effect)))
		picker.add_icon_item(icon_texture, "%s  [v%d]" % [label, version])
		picker.set_item_metadata(picker.item_count - 1, choice.duplicate())

func _select_exact(picker: OptionButton, definition_id: String, version: int, instance_id: String = "", master_instance_id: String = "", slave_instance_id: String = "") -> void:
	if definition_id.is_empty() or version <= 0:
		return
	for index in range(1, picker.item_count):
		var metadata: Dictionary = picker.get_item_metadata(index)
		if String(metadata.get("id", "")) == definition_id and int(metadata.get("version", 0)) == version:
			if not instance_id.is_empty() and String(metadata.get("instanceId", "")) != instance_id:
				continue
			if not master_instance_id.is_empty() and String(metadata.get("masterInstanceId", "")) != master_instance_id:
				continue
			if not slave_instance_id.is_empty() and String(metadata.get("slaveInstanceId", "")) != slave_instance_id:
				continue
			picker.select(index)
			return

func _select_instance(picker: OptionButton, instance_id: String) -> void:
	if instance_id.is_empty():
		return
	for index in range(1, picker.item_count):
		var metadata: Dictionary = picker.get_item_metadata(index)
		if String(metadata.get("instanceId", "")) == instance_id:
			picker.select(index)
			return

func _set_icon_for_selection(icon: TextureRect, picker: OptionButton, category: String) -> void:
	var choice := _selected_choice(picker)
	_set_icon_texture(icon, choice.get("iconTexture"), category)

func _selected_choice(picker: OptionButton) -> Dictionary:
	if picker.selected <= 0 or picker.selected >= picker.item_count:
		return {}
	var value: Variant = picker.get_item_metadata(picker.selected)
	return value if value is Dictionary else {}

func _on_ship_selected(index: int) -> void:
	if _suppress_picker_events:
		return
	if index <= 0 or index >= _ship_picker.item_count:
		return
	var raw_choice: Variant = _ship_picker.get_item_metadata(index)
	if not (raw_choice is Dictionary):
		_status_label.text = "飞船选择失败：下拉项没有候选实例元数据。"
		push_warning("[Hangar] ship picker row %d has no Dictionary metadata." % index)
		return
	# Do not clear/rebuild an OptionButton while its item_selected signal is
	# dispatching. Commit on the next idle turn, then render from the draft.
	var choice: Dictionary = raw_choice.duplicate(true)
	print("[Hangar] ship picker event received: index=%d candidate=%s@%d#%s" % [
		index, String(choice.get("id", "")), int(choice.get("version", 0)), String(choice.get("instanceId", ""))
	])
	call_deferred("_commit_ship_selection", choice)

func _commit_ship_selection(choice: Dictionary) -> void:
	if not is_instance_valid(_controller):
		return
	var definition_id := String(choice.get("id", ""))
	var definition_version := int(choice.get("version", 0))
	var instance_id := String(choice.get("instanceId", ""))
	if not _controller.set_ship(definition_id, definition_version, instance_id):
		_render_view_model(_controller.get_view_model())
		return
	var committed: Dictionary = _controller.get_view_model().get("selection", {})
	var confirmed := (
		String(committed.get("shipId", "")) == definition_id
		and int(committed.get("shipVersion", 0)) == definition_version
		and String(committed.get("shipInstanceId", "")) == instance_id
	)
	if not confirmed:
		_status_label.text = "飞船选择未提交：装配草稿与候选实例不一致。"
		push_error("[Hangar] ship commit mismatch: candidate=%s@%d#%s draft=%s@%d#%s" % [
			definition_id, definition_version, instance_id,
			String(committed.get("shipId", "")), int(committed.get("shipVersion", 0)), String(committed.get("shipInstanceId", ""))
		])
		_render_view_model(_controller.get_view_model())
		return
	print("[Hangar] ship selection committed: %s@%d#%s" % [definition_id, definition_version, instance_id])
	_render_view_model(_controller.get_view_model())

func _on_parser_selected(index: int) -> void:
	if _suppress_picker_events:
		return
	var choice := _selected_choice(_parser_picker)
	if not choice.is_empty():
		_set_icon_texture(_primary_icons.parser, choice.get("iconTexture"), "parser")
		_controller.set_parser(String(choice.get("id", "")), int(choice.get("version", 0)), parser_slot_id, String(choice.get("instanceId", "")))

func _on_workshop_selected(index: int) -> void:
	if _suppress_picker_events:
		return
	_apply_workshop_slot_selection()

func _on_master_workshop_selected(index: int) -> void:
	if _suppress_picker_events:
		return
	_set_icon_for_selection(_primary_icons.workshop, _master_workshop_picker, "workshop")
	_apply_workshop_slot_selection()

func _on_slave_workshop_selected(index: int) -> void:
	if _suppress_picker_events:		return
	_apply_workshop_slot_selection()

func _apply_workshop_slot_selection() -> void:
	var world := _selected_choice(_workshop_picker)
	if world.is_empty():
		return
	var master_instance_id := ""
	var slave_instance_id := ""
	if board_definition != null:
		var master_assignment := _controller.get_assignment(_master_workshop_slot_id)
		var slave_assignment := _controller.get_assignment(_slave_workshop_slot_id)
		master_instance_id = String(master_assignment.get("ownedInstanceId", ""))
		slave_instance_id = String(slave_assignment.get("ownedInstanceId", ""))
	else:
		var master := _selected_choice(_master_workshop_picker)
		var slave := _selected_choice(_slave_workshop_picker)
		master_instance_id = String(master.get("instanceId", ""))
		slave_instance_id = String(slave.get("instanceId", ""))
	_controller.set_workshop(
		String(world.get("id", "")), int(world.get("version", 0)),
		master_instance_id, slave_instance_id
	)

func _rebuild_board_slot_section(inventory: Dictionary, selection: Dictionary) -> void:
	for child in _board_slot_section.get_children():
		child.queue_free()
	_board_slot_pickers.clear()
	_board_slot_section.visible = board_definition != null
	if board_definition == null:
		return
	_add_section_title(_board_slot_section, "电路板 · 元件安装槽位")
	var world_key := String(selection.get("workshopId", "")) + "@" + str(int(selection.get("workshopVersion", 0)))
	var previous_area := ""
	for slot in board_definition.slots:
		if slot == null:
			continue
		if slot.area_id != previous_area:
			previous_area = slot.area_id
			var area_labels := {
				"workshop": "工作区",
				"decomposition": "分解区",
				"orders": "订单区",
				"production": "生产区"
			}
			_add_section_title(_board_slot_section, String(area_labels.get(previous_area, previous_area)))
		var slot_id := String(slot.slot_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_board_slot_section.add_child(row)
		var category := _board_slot_icon_category(slot.component_kind)
		var icon := _make_icon(category, 44)
		row.add_child(icon)
		var label := Label.new()
		label.text = "%s  ·  %s%s" % [
			String(slot.display_name),
			slot.component_kind,
			"  /  " + slot.role_id if slot.component_kind == "workshop" else ("  /  " + slot.control_area if slot.component_kind == "skill" else "")
		]
		label.custom_minimum_size.x = 190
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		var picker := OptionButton.new()
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.add_item("未安装（点击选择元件）")
		var choices := _board_slot_choices(inventory, slot, world_key)
		for choice in choices:
			var choice_icon: Variant = choice.get("iconTexture")
			if not (choice_icon is Texture2D):
				choice_icon = load(String(FALLBACK_ICONS.get(category, FALLBACK_ICONS.effect)))
			var choice_label := "%s  [v%d] · Lv%d · %s" % [
				String(choice.get("label", choice.get("id", ""))),
				int(choice.get("version", 0)),
				int(choice.get("level", 1)),
				String(choice.get("instanceId", ""))
			]
			picker.add_icon_item(choice_icon, choice_label)
			picker.set_item_metadata(picker.item_count - 1, choice.duplicate(true))
			picker.set_item_tooltip(picker.item_count - 1, String(choice.get("description", "")))
		var assignment := _controller.get_assignment(slot_id)
		var selected_instance := String(assignment.get("ownedInstanceId", ""))
		for item_index in range(1, picker.item_count):
			var candidate: Dictionary = picker.get_item_metadata(item_index)
			if String(candidate.get("instanceId", "")) == selected_instance and not selected_instance.is_empty():
				picker.select(item_index)
				_set_icon_texture(icon, candidate.get("iconTexture"), category)
				break
		picker.item_selected.connect(_on_board_slot_selected.bind(slot_id, picker))
		_board_slot_pickers[slot_id] = picker
		row.add_child(picker)
		if not bool(slot.required):
			var optional := Label.new()
			optional.text = "可选"
			optional.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(optional)

func _board_slot_choices(inventory: Dictionary, slot: SpaceHangarBoardSlotDefinition, world_key: String) -> Array:
	var collection_key := ""
	match slot.component_kind:
		"workshop":
			collection_key = "workshopInstanceChoices"
		"ore_parser":
			collection_key = "parserChoices"
		"skill":
			collection_key = "skillChoices"
		"production_device":
			collection_key = "deviceChoices"
		_:
			return []
	var raw_choices: Variant = inventory.get(collection_key, [])
	if not (raw_choices is Array):
		return []
	var result: Array = []
	# One owned instance can occupy only one physical board slot. Remove instances
	# already installed elsewhere so the UI cannot offer an invalid duplicate.
	var used_elsewhere := {}
	if _controller != null and board_definition != null:
		for other_slot in board_definition.slots:
			if other_slot == null or String(other_slot.slot_id) == String(slot.slot_id):
				continue
			var other_assignment := _controller.get_assignment(String(other_slot.slot_id))
			var used_id := String(other_assignment.get("ownedInstanceId", ""))
			if not used_id.is_empty():
				used_elsewhere[used_id] = true
	for raw_choice in raw_choices:
		if not (raw_choice is Dictionary):
			continue
		var choice: Dictionary = raw_choice
		var candidate_instance_id := String(choice.get("instanceId", ""))
		if not candidate_instance_id.is_empty() and used_elsewhere.has(candidate_instance_id):
			continue
		if slot.component_kind == "workshop" and not world_key.ends_with("@0") and world_key != "@" and not choice.get("compatibleWorldKeys", []).has(world_key):
			continue
		if slot.component_kind == "skill" and not choice.get("allowedControlAreas", []).has(slot.control_area):
			continue
		result.append(choice.duplicate(true))
	return result

func _board_slot_icon_category(component_kind: String) -> String:
	match component_kind:
		"workshop": return "workshop"
		"ore_parser": return "parser"
		"skill": return "skill"
		"production_device": return "device"
	return "effect"

func _on_board_slot_selected(index: int, slot_id: String, picker: OptionButton) -> void:
	if _suppress_picker_events:
		return
	if index <= 0:
		_controller.unassign_slot(slot_id)
		return
	var choice: Variant = picker.get_item_metadata(index)
	if not (choice is Dictionary):
		return
	var instance_id := String(choice.get("instanceId", ""))
	if instance_id.is_empty():
		return
	if _controller.assign_instance(slot_id, instance_id):
		var slot := board_definition.resolve_slot(slot_id)
		if slot != null and slot.component_kind == "workshop" and _selected_choice(_workshop_picker).is_empty() == false:
			_apply_workshop_slot_selection()

func _rebuild_device_section(device_choices: Variant, selected_devices: Variant) -> void:
	for child in _device_section.get_children():
		child.queue_free()
	_device_pickers.clear()
	if device_slot_ids.is_empty():
		if _array_size(device_choices) > 0:
			_add_section_title(_device_section, "生产设备（等待游戏流程提供槽位）")
		return
	_add_section_title(_device_section, "生产设备槽位")
	for raw_slot in device_slot_ids:
		var slot_id := String(raw_slot).strip_edges()
		if slot_id.is_empty() or _device_pickers.has(slot_id):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_device_section.add_child(row)
		var icon := _make_icon("device", 48)
		row.add_child(icon)
		var label := Label.new()
		label.text = slot_id
		label.custom_minimum_size.x = 150
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		var picker := OptionButton.new()
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.add_item("空槽位")
		for choice in device_choices:
			if choice is Dictionary:
				var item_icon: Variant = choice.get("iconTexture")
				if not (item_icon is Texture2D):
					item_icon = load(FALLBACK_ICONS.device)
				picker.add_icon_item(item_icon, "%s  [v%d] · Lv%d · %s" % [String(choice.get("label", choice.get("id", ""))), int(choice.get("version", 0)), int(choice.get("level", 1)), String(choice.get("instanceId", ""))])
				picker.set_item_metadata(picker.item_count - 1, choice.duplicate())
		row.add_child(picker)
		var existing := _find_device_selection(selected_devices, slot_id)
		if not existing.is_empty():
			for item_index in range(1, picker.item_count):
				var candidate: Dictionary = picker.get_item_metadata(item_index)
				if String(candidate.get("id", "")) == String(existing.get("definitionId", "")) and int(candidate.get("version", 0)) == int(existing.get("definitionVersion", 0)) and String(candidate.get("instanceId", "")) == String(existing.get("instanceId", "")):
					picker.select(item_index)
					_set_icon_texture(icon, candidate.get("iconTexture"), "device")
					break
		picker.item_selected.connect(_on_device_selected.bind(slot_id, picker, icon))
		_device_pickers[slot_id] = picker

func _find_device_selection(raw_selections: Variant, slot_id: String) -> Dictionary:
	if raw_selections is Array:
		for value in raw_selections:
			if value is Dictionary and String(value.get("slotId", "")) == slot_id:
				return value
	return {}

func _on_device_selected(index: int, slot_id: String, picker: OptionButton, icon: TextureRect) -> void:
	if _suppress_picker_events:
		return
	if index <= 0:
		_controller.remove_device(slot_id)
		_set_icon_texture(icon, null, "device")
		return
	var choice: Dictionary = picker.get_item_metadata(index)
	if _controller.set_device(slot_id, String(choice.get("id", "")), int(choice.get("version", 0)), String(choice.get("instanceId", ""))):
		_set_icon_texture(icon, choice.get("iconTexture"), "device")

func _rebuild_skill_section(skill_choices: Variant, selected_skills: Variant) -> void:
	for child in _skill_section.get_children():
		child.queue_free()
	if skill_order_bindings.is_empty():
		if _array_size(skill_choices) > 0:
			_add_section_title(_skill_section, "技能绑定（等待游戏流程提供订单键）")
		return
	_add_section_title(_skill_section, "订单区 · 技能元件槽位")
	for binding in skill_order_bindings:
		if not (binding is Dictionary):
			continue
		var order_key := String(binding.get("orderDefinitionKey", "")).strip_edges()
		var slot_control_area := String(binding.get("controlArea", ""))
		if order_key.is_empty():
			continue
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_skill_section.add_child(row)
		var row_title := Label.new()
		row_title.text = String(binding.get("label", order_key)) + (" · 可选槽位" if not bool(binding.get("required", true)) else "")
		row.add_child(row_title)
		var controls := HBoxContainer.new()
		controls.add_theme_constant_override("separation", 8)
		row.add_child(controls)
		var icon := _make_icon("skill", 48)
		controls.add_child(icon)
		var primary_shape_label := Label.new()
		primary_shape_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		controls.add_child(primary_shape_label)
		var skill_picker := OptionButton.new()
		skill_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		skill_picker.add_item("不装备技能")
		for choice in skill_choices:
			if choice is Dictionary:
				if slot_control_area in ["Active", "Passive"] and not choice.get("allowedControlAreas", []).has(slot_control_area):
					continue
				var item_icon: Variant = choice.get("iconTexture")
				if not (item_icon is Texture2D):					item_icon = load(FALLBACK_ICONS.skill)
				var primary_shape := String(choice.get("primaryShape", ""))
				var category := String(choice.get("category", ""))
				var category_label := String({
					"Offense": "攻击",
					"Defense": "防御",
					"Support": "支援",
					"Reconnaissance": "侦察",
					"Utility": "辅助"
				}.get(category, category))
				var choice_name := String(choice.get("label", choice.get("id", "")))
				var owned_suffix := " · Lv%d · %s" % [int(choice.get("level", 1)), String(choice.get("instanceId", ""))] if choice.has("instanceId") else ""
				var choice_text := "【%s】%s  [v%d]%s" % [category_label, choice_name, int(choice.get("version", 0)), owned_suffix] if not category_label.is_empty() else "%s  [v%d]%s" % [choice_name, int(choice.get("version", 0)), owned_suffix]
				if not primary_shape.is_empty():
					choice_text += "  ·  主形 %s %s" % [ShapeVisuals.glyph_for(primary_shape), primary_shape]
				skill_picker.add_icon_item(item_icon, choice_text)
				skill_picker.set_item_metadata(skill_picker.item_count - 1, choice.duplicate())
				skill_picker.set_item_tooltip(skill_picker.item_count - 1, String(choice.get("description", "")))
		controls.add_child(skill_picker)
		var area_picker := OptionButton.new()
		area_picker.custom_minimum_size.x = 145
		area_picker.add_item("控制区域")
		controls.add_child(area_picker)
		var existing := _find_skill_selection(selected_skills, order_key)
		var pending: Dictionary = _pending_skill_choices.get(order_key, {})
		var wanted_id := String(pending.get("id", existing.get("skillId", "")))
		var wanted_version := int(pending.get("version", existing.get("definitionVersion", 0)))
		var wanted_instance_id := String(pending.get("instanceId", existing.get("instanceId", "")))
		for item_index in range(1, skill_picker.item_count):
			var candidate: Dictionary = skill_picker.get_item_metadata(item_index)
			if String(candidate.get("id", "")) == wanted_id and int(candidate.get("version", 0)) == wanted_version and (wanted_instance_id.is_empty() or String(candidate.get("instanceId", "")) == wanted_instance_id):
				skill_picker.select(item_index)
				_set_icon_texture(icon, candidate.get("iconTexture"), "skill")
				_set_primary_shape_label(primary_shape_label, candidate)
				var selected_area := String(pending.get("controlArea", existing.get("controlArea", slot_control_area)))
				_populate_control_areas(area_picker, candidate.get("allowedControlAreas", []), selected_area)
				area_picker.disabled = slot_control_area in ["Active", "Passive"]
				break
		skill_picker.item_selected.connect(_on_skill_selected.bind(order_key, skill_picker, area_picker, icon, primary_shape_label, slot_control_area))
		area_picker.item_selected.connect(_on_skill_area_selected.bind(order_key, skill_picker, area_picker))
		if skill_picker.selected == 0:
			area_picker.disabled = true

func _find_skill_selection(raw_selections: Variant, order_key: String) -> Dictionary:
	if raw_selections is Array:
		for value in raw_selections:
			if value is Dictionary and String(value.get("orderDefinitionKey", "")) == order_key:
				return value
	return {}

func _populate_control_areas(area_picker: OptionButton, raw_areas: Variant, selected_area: String = "") -> void:
	area_picker.clear()
	area_picker.add_item("控制区域")
	if raw_areas is Array:
		for area in raw_areas:
			area_picker.add_item(String(area))
			if String(area) == selected_area:
				area_picker.select(area_picker.item_count - 1)
	area_picker.disabled = area_picker.item_count <= 1

func _on_skill_selected(index: int, order_key: String, skill_picker: OptionButton, area_picker: OptionButton, icon: TextureRect, primary_shape_label: Label, slot_control_area: String = "") -> void:
	if index <= 0:
		_pending_skill_choices.erase(order_key)
		_controller.remove_skill(order_key)
		_populate_control_areas(area_picker, [])
		_set_icon_texture(icon, null, "skill")
		_set_primary_shape_label(primary_shape_label, {})
		return
	var choice: Dictionary = skill_picker.get_item_metadata(index)
	_pending_skill_choices[order_key] = choice.duplicate(true)
	var selected_area := slot_control_area if slot_control_area in ["Active", "Passive"] else ""
	_populate_control_areas(area_picker, choice.get("allowedControlAreas", []), selected_area)
	area_picker.disabled = not selected_area.is_empty()
	_set_icon_texture(icon, choice.get("iconTexture"), "skill")
	_set_primary_shape_label(primary_shape_label, choice)
	if not selected_area.is_empty():
		_controller.set_skill(order_key, String(choice.get("id", "")), int(choice.get("version", 0)), selected_area, String(choice.get("instanceId", "")))

func _set_primary_shape_label(label: Label, choice: Dictionary) -> void:
	var primary_shape := String(choice.get("primaryShape", ""))
	if primary_shape.is_empty():
		label.text = ""
		label.add_theme_color_override("font_color", ShapeVisuals.NEUTRAL)
		return
	label.text = "%s 主形 %s" % [ShapeVisuals.glyph_for(primary_shape), primary_shape]
	label.add_theme_color_override("font_color", ShapeVisuals.color_for(primary_shape))

func _on_skill_area_selected(index: int, order_key: String, skill_picker: OptionButton, area_picker: OptionButton) -> void:
	if index > 0:
		_apply_skill_binding(order_key, skill_picker, area_picker)

func _apply_skill_binding(order_key: String, skill_picker: OptionButton, area_picker: OptionButton) -> void:
	var skill := _selected_choice(skill_picker)
	if skill.is_empty() or area_picker.selected <= 0:
		return
	var selected_area := area_picker.get_item_text(area_picker.selected)
	var pending: Dictionary = _pending_skill_choices.get(order_key, skill.duplicate(true))
	pending["controlArea"] = selected_area
	_pending_skill_choices[order_key] = pending
	if _controller.set_skill(order_key, String(skill.get("id", "")), int(skill.get("version", 0)), selected_area, String(skill.get("instanceId", ""))):
		_pending_skill_choices.erase(order_key)

func _rebuild_effect_section(effect_choices: Variant) -> void:
	for child in _effect_section.get_children():
		child.queue_free()
	if _array_size(effect_choices) == 0:
		var empty_label := Label.new()
		empty_label.text = "尚无效果定义"
		_effect_section.add_child(empty_label)
		return
	var heading := Label.new()
	heading.text = "效果定义（由技能引用）"
	_effect_section.add_child(heading)
	for choice in effect_choices:
		if not (choice is Dictionary):
			continue
		var row := HBoxContainer.new()
		_effect_section.add_child(row)
		var icon := _make_icon("effect", 34)
		_set_icon_texture(icon, choice.get("iconTexture"), "effect")
		row.add_child(icon)
		var label := Label.new()
		label.text = "%s  [v%d]" % [String(choice.get("label", choice.get("id", ""))), int(choice.get("version", 0))]
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)

func _on_duration_changed(value: float) -> void:
	if value > 0.0:
		_controller.set_expected_battle_duration(value)
	else:
		_update_build_enabled(_controller.get_view_model())

func _on_refresh_pressed() -> void:
	_refresh_confirmation.popup_centered()

func _on_refresh_confirmed() -> void:
	_controller.refresh_inventory()
	if _duration_picker.value > 0.0:
		_controller.set_expected_battle_duration(_duration_picker.value)

func _on_build_pressed() -> void:
	# The picker is the visible source of the player's current ship choice.
	# Reconcile it at the final assembly boundary as well as handling item_selected,
	# so a missed/stale UI signal cannot leave the domain draft without a ship.
	var ship_choice := _selected_choice(_ship_picker)
	if ship_choice.is_empty():
		_status_label.text = "尚未选择飞船：请在「飞船定义」中选择一艘已拥有的飞船。"
		_update_build_enabled(_controller.get_view_model())
		return
	if not _controller.set_ship(
		String(ship_choice.get("id", "")),
		int(ship_choice.get("version", 0)),
		String(ship_choice.get("instanceId", ""))
	):
		_status_label.text = "飞船选择未能写入装配草稿：当前目录中的飞船实例已失效，请重新读取目录后再选。"
		return
	var snapshot := _controller.build_loadout_snapshot()
	if snapshot == null:
		_status_label.text = String(_controller.get_view_model().get("lastError", "装配快照构建失败"))
		return
	var game_scene := load("res://scenes/game/Game.tscn") as PackedScene
	if game_scene == null:
		_status_label.text = "战斗场景不可用，无法启动。"
		return
	var game := game_scene.instantiate()
	if game == null:
		_status_label.text = "战斗场景实例化失败。"
		return
	var commit_callback := _create_order_effect_commit_callback(game, snapshot) if not snapshot.order_definition_keys().is_empty() else Callable()
	if not SpaceHangarBattleLauncher.launch_new_battle(
		get_tree().root, game, snapshot, commit_callback, _selected_stage
	):
		if not game.is_inside_tree():
			game.free()
		_status_label.text = "战斗启动被拒绝：请检查 Core 订单可行性、效果提交回调和关卡配置。"
		return
	visible = false

func _create_order_effect_commit_callback(game: Node, loadout: SpaceBattleLoadoutSnapshot) -> Callable:
	var bundle := _preparation.create_catalog_bundle() if _preparation != null else null
	if bundle == null or bundle.effect_catalog == null:
		return Callable()
	var committer := SpaceOrderEffectCommitter.new()
	var store := SpaceBattleEffectStateStore.new()
	var configured := false
	var callback := func(event: Dictionary, binding: Dictionary, next_dispatcher_state: Dictionary) -> bool:
		var player_node := game.get_node_or_null("Arena/Player")
		if player_node == null:
			return false
		var manager := player_node.get("effects") as StatusEffectManager
		if manager == null:
			return false
		if not configured:
			var target_resolver := func(_effect_binding: Dictionary, _event: Dictionary) -> Node:
				return player_node
			var checkpoint_provider := func() -> Dictionary:
				return game.call("capture_jar_space_runtime_checkpoint")
			if not committer.configure(bundle.effect_catalog, manager, store, loadout, target_resolver, checkpoint_provider):
				return false
			configured = true
		return committer.commit(event, binding, next_dispatcher_state)
	return callback

func _update_build_enabled(view_model: Dictionary) -> void:
	if not is_instance_valid(_build_button):
		return
	var inventory: Dictionary = view_model.get("inventory", {})
	var devices_exist := _array_size(inventory.get("deviceChoices", [])) > 0
	var skills_exist := _array_size(inventory.get("skillChoices", [])) > 0
	var binding_configuration_complete := board_definition != null or ((not devices_exist or not device_slot_ids.is_empty()) and (not skills_exist or not skill_order_bindings.is_empty()))
	var blockers: Array[String] = []
	if not _board_configuration_valid:
		blockers.append("电路板定义无效")
	if not bool(view_model.get("canBuild", false)):
		var selection: Dictionary = view_model.get("selection", {})
		if String(selection.get("shipId", "")).is_empty():
			blockers.append("尚未提交飞船选择")
		if board_definition != null:
			for issue in _controller.validate_assignments():
				blockers.append(String(issue))
		for issue in view_model.get("validationErrors", []):
			blockers.append(String(issue))
	if _duration_picker.value <= 0.0:
		blockers.append("战斗时长无效")
	if not binding_configuration_complete:
		blockers.append("设备/技能槽位绑定配置不完整")
	if not _slot_configuration_is_valid():
		blockers.append("机库槽位配置无效")
	_build_button.disabled = not blockers.is_empty()
	_build_button.tooltip_text = "无法进入战斗：\n" + "\n".join(blockers) if not blockers.is_empty() else "装配条件已满足，可以进入战斗。"

func _slot_configuration_is_valid() -> bool:
	if parser_slot_id.strip_edges().is_empty():
		return false
	var seen_device_slots := {}
	for raw_slot in device_slot_ids:
		var slot_id := String(raw_slot).strip_edges()
		if slot_id.is_empty() or slot_id == parser_slot_id or seen_device_slots.has(slot_id):
			return false
		seen_device_slots[slot_id] = true
	var seen_order_keys := {}
	for binding in skill_order_bindings:
		if not (binding is Dictionary):
			return false
		var order_key := String(binding.get("orderDefinitionKey", "")).strip_edges()
		if order_key.is_empty() or seen_order_keys.has(order_key):
			return false
		seen_order_keys[order_key] = bool(binding.get("required", false))
	var selection: Dictionary = {}
	if _controller != null:
		var raw_selection: Variant = _controller.get_view_model().get("selection", {})
		if raw_selection is Dictionary:
			selection = raw_selection
	var selected_order_keys := {}
	for selected in selection.get("skillSelections", []):
		if selected is Dictionary:
			selected_order_keys[String(selected.get("orderDefinitionKey", ""))] = true
	for order_key in seen_order_keys:
		if bool(seen_order_keys[order_key]) and not selected_order_keys.has(order_key):
			return false
	return true

func _identity_is_supplied() -> bool:
	return (
		String(loadout_identity.get("shipWorldId", "")).strip_edges() != ""
		and String(loadout_identity.get("loadoutId", "")).strip_edges() != ""
		and int(loadout_identity.get("loadoutVersion", 0)) > 0
	)

func _array_size(value: Variant) -> int:
	return value.size() if value is Array else 0

func _on_progression_state_changed(state: SpacePlayerProgressionState) -> void:
	if _preparation == null:
		return
	_preparation.player_progression_state = state
	if _controller != null:
		_controller.refresh_inventory()
