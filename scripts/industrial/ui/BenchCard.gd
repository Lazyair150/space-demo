extends PanelContainer
## 装配台卡片（原 `play.html` 的主台/从台面板）。
##
## 只说三件事：这台能放什么（标记）、存了什么（舱段/工质）、装了多少（容量）。
## 容量上限对**每种工质各自**生效，不能相加 —— 这是 Core 的语义，界面不许改写。

signal picker_requested(role: String)

const UiKit := preload("res://scripts/industrial/ui/UiKit.gd")

var role := "master"
## 上一次 bind 时这台是不是空（主控用它判断"这个按钮是换台还是撤台"）。
var workshop_empty := true

var _built := false
var _body: VBoxContainer
var _head: Label
var _marks: Label
var _ban: Label
var _jars: Label
var _liquids: VBoxContainer
var _pick_button: Button


func set_role(value: String) -> void:
	role = value


## 上一次 bind 时这台是不是空的（主控据此决定按钮语义）。
func is_empty_workshop() -> bool:
	return workshop_empty


func _ready() -> void:
	if _built:
		return
	_built = true
	var box := UiKit.vbox(4)
	add_child(box)

	var head_row := UiKit.hbox(8)
	_head = UiKit.label("——", UiKit.FONT_TITLE, UiKit.ACCENT)
	head_row.add_child(_head)
	head_row.add_child(UiKit.spacer())
	_pick_button = UiKit.small_button("换台", 92)
	_pick_button.pressed.connect(func() -> void: picker_requested.emit(role))
	head_row.add_child(_pick_button)
	box.add_child(head_row)

	_marks = UiKit.wrap_label("", UiKit.FONT_SMALL, UiKit.MUTED)
	box.add_child(_marks)
	_ban = UiKit.wrap_label("", UiKit.FONT_SMALL, UiKit.WARN)
	box.add_child(_ban)
	_jars = UiKit.label("", UiKit.FONT_BODY, UiKit.TEXT)
	box.add_child(_jars)
	_liquids = UiKit.vbox(2)
	box.add_child(_liquids)


## `workshop` 为空字典表示这台还没选（空态）。
## 执行中锁定：换台会让"这一步用的是哪台"失去定义，所以过程在跑时禁用换台按钮。
func set_locked(locked: bool) -> void:
	if _pick_button != null:
		_pick_button.disabled = locked


func bind(workshop: Dictionary) -> void:
	if not _built:
		_ready()

	var is_empty := workshop.is_empty()
	workshop_empty = is_empty
	if role == "master":
		_head.text = "主装配台" if is_empty else "主装配台 · %s" % str(workshop.get("name", ""))
		_pick_button.text = "换主台"
	else:
		_head.text = "副装配台" if is_empty else "副装配台 · %s" % str(workshop.get("name", ""))
		_pick_button.text = "撤掉副台" if not is_empty else "选副台"

	if is_empty:
		_marks.text = "还没有选这台。" if role == "master" else "还没有副装配台（可选）。"
		_ban.text = ""
		_jars.text = ""
		UiKit.clear_children(_liquids)
		return

	var base: Array = workshop.get("baseMarks", [])
	var extra: Array = workshop.get("additionalMarks", [])
	_marks.text = "基础舱段：%s　·　附加舱段：%s" % [
		_join(base), _join(extra) if not extra.is_empty() else "无"
	]
	var ban: Array = workshop.get("ban", [])
	_ban.text = "禁装工质：%s（能存不能用）" % _join(ban) if not ban.is_empty() else ""

	var jars: Array = workshop.get("jars", [])
	var max_jars := int(workshop.get("maxJars", 0))
	_jars.text = "舱段 %d 只%s" % [
		jars.size(),
		" / %d" % max_jars if max_jars > 0 else "",
	]

	UiKit.clear_children(_liquids)
	var liquids: Dictionary = workshop.get("liquids", {})
	var max_liquids := int(workshop.get("maxLiquids", 0))
	for name_text in liquids.keys():
		var line := "工质 %s：%d%s" % [
			str(name_text),
			int(liquids[name_text]),
			" / %d" % max_liquids if max_liquids > 0 else "",
		]
		_liquids.add_child(UiKit.label(line, UiKit.FONT_SMALL, UiKit.TEXT))

	# 舱段构成：按形状计数，带上"装了工质"的只数
	var by_shape := {}
	var filled := 0
	for jar in jars:
		var shape := str(jar.get("shape", ""))
		by_shape[shape] = int(by_shape.get(shape, 0)) + 1
		if jar.get("liquid", null) != null:
			filled += 1
	if jars.size() > 0:
		var parts: Array[String] = []
		for shape in by_shape.keys():
			parts.append("%s×%d" % [str(shape), int(by_shape[shape])])
		_liquids.add_child(UiKit.label("构成：%s" % "、".join(parts), UiKit.FONT_SMALL, UiKit.MUTED))
		if filled > 0:
			_liquids.add_child(UiKit.label("其中装了工质：%d 只" % filled, UiKit.FONT_SMALL, UiKit.MUTED))


func _join(items: Array) -> String:
	var parts: Array[String] = []
	for item in items:
		parts.append(str(item))
	return "、".join(parts) if not parts.is_empty() else "无"
