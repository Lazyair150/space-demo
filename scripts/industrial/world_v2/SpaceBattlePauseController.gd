extends CanvasLayer
class_name SpaceBattlePauseController
## Sole player-facing pause authority for the combat scene.
## The pause UI remains processable while the inherited gameplay tree is paused.

signal pause_changed(is_paused: bool, reason: String)

var _paused := false
var _reason := ""
var _overlay: Control
var _reason_label: Label
var _title_label: Label
var _primary_button: Button
var _menu_button: Button
var _pause_button: Button
var _faulted := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()
	_build_pause_button()
	_sync_overlay()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		set_paused(not _paused, "player")
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not _paused:
		set_paused(true, "window_focus_lost")

func is_paused() -> bool:
	return _paused

## Used only after a saved battle has been fully restored. The Host is paused
## before the SceneTree gate closes, so no first-frame simulation can escape.
func enter_resume_ready() -> bool:
	if _paused or GameFlow.snapshot().get("battlePhase", "") != "RESUME_READY":
		return false
	var tree := get_tree()
	var host := tree.root.get_node_or_null("WorldV2ShipHost")
	if host == null or not host.has_method("PauseShipWorld"):
		return false
	host.call("PauseShipWorld")
	_paused = true
	_reason = "resume_ready"
	tree.paused = true
	_sync_overlay()
	pause_changed.emit(true, _reason)
	return true

func show_fault(reason: String) -> void:
	_faulted = true
	_paused = false
	_reason = reason.strip_edges()
	if is_instance_valid(_title_label):
		_title_label.text = "战斗已停止  /  BATTLE FAULT"
	if is_instance_valid(_primary_button):
		_primary_button.text = "返回主菜单  /  Main Menu"
	_sync_overlay()
	pause_changed.emit(false, "faulted")

func _on_primary_action() -> void:
	if _faulted:
		_request_main_menu()
	else:
		set_paused(false)

func _on_menu_action() -> void:
	_request_main_menu()

## Normal and faulted exits must use the Game composition root. GameFlow changes
## current_scene (Hangar), but the battle is a separate /root child and must also
## be disposed by its owner after the transition is accepted.
func _request_main_menu() -> void:
	var battle := get_parent()
	if battle == null or not battle.has_method("end_battle_for_menu"):
		push_error("[BattlePause] Main-menu exit has no battle lifecycle owner")
		return
	_menu_button.disabled = true
	_primary_button.disabled = true
	_overlay.visible = false
	if not bool(battle.call("end_battle_for_menu")):
		_faulted = true
		_reason = "战斗已终止，但主菜单切换失败；可以重试"
		_title_label.text = "战斗已结束  /  BATTLE ENDED"
		_primary_button.text = "重试返回主菜单  /  Retry"
		_primary_button.disabled = false
		_menu_button.disabled = false
		_menu_button.visible = false
		_overlay.visible = true

func _on_pause_button_pressed() -> void:
	set_paused(true, "player")

func set_paused(value: bool, reason: String = "player") -> void:
	if _faulted or not is_inside_tree() or _paused == value:
		return
	var tree := get_tree()
	var host := tree.root.get_node_or_null("WorldV2ShipHost")
	if value:
		var pause_reason := GameFlow.PauseReason.WINDOW_FOCUS_LOST if reason == "window_focus_lost" else GameFlow.PauseReason.PLAYER
		if not GameFlow.pause_battle(pause_reason):
			return
		if host != null:
			host.call("PauseShipWorld")
		_paused = true
		_reason = reason
		tree.paused = true
	else:
		var resumed := GameFlow.confirm_resume_battle() if _reason == "resume_ready" else GameFlow.resume_battle()
		if not resumed:
			return
		_paused = false
		_reason = ""
		tree.paused = false
		if host != null:
			host.call("ResumeShipWorld")
	_sync_overlay()
	pause_changed.emit(_paused, _reason)

func _build_pause_button() -> void:
	_pause_button = Button.new()
	_pause_button.name = "PauseButton"
	_pause_button.text = "Ⅱ  暂停"
	_pause_button.tooltip_text = "暂停战斗（Esc）"
	_pause_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_button.anchor_left = 1.0
	_pause_button.anchor_right = 1.0
	_pause_button.anchor_top = 0.0
	_pause_button.anchor_bottom = 0.0
	_pause_button.offset_left = -124.0
	_pause_button.offset_top = 18.0
	_pause_button.offset_right = -24.0
	_pause_button.offset_bottom = 62.0
	_pause_button.pressed.connect(_on_pause_button_pressed)
	add_child(_pause_button)

func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	add_child(_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.025, 0.045, 0.82)
	_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 230)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	_title_label = Label.new()
	_title_label.text = "PAUSED  /  已暂停"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 26)
	column.add_child(_title_label)
	_reason_label = Label.new()
	_reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason_label.custom_minimum_size = Vector2(280, 54)
	column.add_child(_reason_label)
	_primary_button = Button.new()
	_primary_button.text = "继续游戏  /  Resume"
	_primary_button.pressed.connect(_on_primary_action)
	column.add_child(_primary_button)
	_menu_button = Button.new()
	_menu_button.text = "返回主菜单  /  Main Menu"
	_menu_button.pressed.connect(_on_menu_action)
	column.add_child(_menu_button)

func _sync_overlay() -> void:
	if not is_instance_valid(_overlay):
		return
	_overlay.visible = _paused or _faulted
	if is_instance_valid(_pause_button):
		_pause_button.visible = not _paused and not _faulted
	if is_instance_valid(_menu_button):
		_menu_button.visible = not _faulted
	if is_instance_valid(_reason_label):
		if _faulted:
			_reason_label.text = _reason if not _reason.is_empty() else "运行时发生故障，模拟已终止"
		elif _reason == "window_focus_lost":
			_reason_label.text = "窗口失焦，等待手动继续"
		elif _reason == "resume_ready":
			_reason_label.text = "存档已恢复。确认后继续战斗"
		else:
			_reason_label.text = "战斗逻辑与 Jar 世界均已冻结"

func _exit_tree() -> void:
	if not _paused:
		return
	# Scene teardown is not a resume command. Release only the engine-wide
	# pause latch; the owning Game node disposes the Host synchronously.
	get_tree().paused = false
	_paused = false
	_reason = ""
