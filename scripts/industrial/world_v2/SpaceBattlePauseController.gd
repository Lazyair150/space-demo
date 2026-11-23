extends CanvasLayer
class_name SpaceBattlePauseController
## Sole player-facing pause authority for the combat scene.
## The pause UI remains processable while the inherited gameplay tree is paused.

signal pause_changed(is_paused: bool, reason: String)

var _paused := false
var _reason := ""
var _overlay: Control
var _reason_label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()
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

func set_paused(value: bool, reason: String = "player") -> void:
	if not is_inside_tree() or _paused == value:
		return
	var tree := get_tree()
	var host := tree.root.get_node_or_null("WorldV2ShipHost")
	if value:
		if host != null:
			host.call("PauseShipWorld")
		_paused = true
		_reason = reason
		tree.paused = true
	else:
		_paused = false
		_reason = ""
		tree.paused = false
		if host != null:
			host.call("ResumeShipWorld")
	_sync_overlay()
	pause_changed.emit(_paused, _reason)

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
	panel.custom_minimum_size = Vector2(320, 170)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var title := Label.new()
	title.text = "PAUSED  /  已暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)
	_reason_label = Label.new()
	_reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_reason_label)
	var resume := Button.new()
	resume.text = "继续游戏  /  Resume"
	resume.pressed.connect(func() -> void: set_paused(false))
	column.add_child(resume)

func _sync_overlay() -> void:
	if not is_instance_valid(_overlay):
		return
	_overlay.visible = _paused
	if is_instance_valid(_reason_label):
		_reason_label.text = "窗口失焦，等待手动继续" if _reason == "window_focus_lost" else "战斗逻辑与 Jar 世界均已冻结"