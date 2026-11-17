extends PanelContainer
## 中央仓库面板：只有数字，没有按钮。
##
## 它是"生产 → 仓库 → 主台"这条链的中点，所以必须同时显示两件容易混的事：
## 仓库里有多少，以及**被丢掉了多少**（丢弃发生在流入/容量钳制时，不是"仓库满了"）。

const UiKit := preload("res://scripts/industrial/ui/UiKit.gd")

var _built := false
var _count: Label
var _shapes: Label
var _liquids: Label
var _discarded: Label


func _ready() -> void:
	if _built:
		return
	_built = true
	var box := UiKit.vbox(4)
	add_child(box)
	box.add_child(UiKit.title("中央仓库"))
	_count = UiKit.label("", UiKit.FONT_BODY, UiKit.TEXT)
	box.add_child(_count)
	_shapes = UiKit.wrap_label("", UiKit.FONT_SMALL, UiKit.MUTED)
	box.add_child(_shapes)
	_liquids = UiKit.wrap_label("", UiKit.FONT_SMALL, UiKit.TEXT)
	box.add_child(_liquids)
	_discarded = UiKit.wrap_label("", UiKit.FONT_SMALL, UiKit.WARN)
	box.add_child(_discarded)


func bind(warehouse: Dictionary) -> void:
	if not _built:
		_ready()

	var jars := int(warehouse.get("jars", 0))
	_count.text = "舱段 %d 只" % jars

	var jar_list: Array = warehouse.get("jarList", [])
	if jar_list.is_empty():
		_shapes.text = ""
	else:
		var by_shape := {}
		for jar in jar_list:
			var shape := str(jar.get("shape", ""))
			by_shape[shape] = int(by_shape.get(shape, 0)) + 1
		var parts: Array[String] = []
		for shape in by_shape.keys():
			parts.append("%s×%d" % [str(shape), int(by_shape[shape])])
		_shapes.text = "构成：%s" % "、".join(parts)

	var liquids: Dictionary = warehouse.get("liquids", {})
	var liquid_parts: Array[String] = []
	for name_text in liquids.keys():
		liquid_parts.append("%s %d" % [str(name_text), int(liquids[name_text])])
	_liquids.text = "工质：%s" % "、".join(liquid_parts) if not liquid_parts.is_empty() else "工质：无"

	var discarded := int(warehouse.get("discardedJars", 0))
	var discarded_liquids: Dictionary = warehouse.get("discardedLiquids", {})
	var liquid_discarded := 0
	for key in discarded_liquids.keys():
		liquid_discarded += int(discarded_liquids[key])
	if discarded > 0 or liquid_discarded > 0:
		_discarded.text = "已丢弃 %d 只舱段、%d 份工质（装配台装不下）。" % [discarded, liquid_discarded]
	else:
		_discarded.text = ""
