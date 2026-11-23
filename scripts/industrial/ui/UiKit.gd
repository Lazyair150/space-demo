extends RefCounted
## Space/Jar presentation helper: palette, panel styling, and common control factories.
##
## View construction only: it does not read world state, issue commands, or interpret domain DTOs.

const BG := Color("0e1117")
const PANEL := Color("161b24")
const PANEL_SOFT := Color("1c2230")
const BORDER := Color("2a3342")
const TEXT := Color("dde5f0")
const MUTED := Color("8792a6")
const ACCENT := Color("f0b45a")
const OK := Color("6fcf97")
const WARN := Color("f2c14e")
const BAD := Color("eb6f6f")

const FONT_SMALL := 12
const FONT_BODY := 14
const FONT_TITLE := 16


static func panel_style(bg: Color = PANEL, border: Color = BORDER) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(10)
	return box


## 一张带描边的面板（面板里的内容自己往里塞）。
static func panel(name_text: String = "", bg: Color = PANEL) -> PanelContainer:
	var node := PanelContainer.new()
	if name_text != "":
		node.name = name_text
	node.add_theme_stylebox_override("panel", panel_style(bg))
	return node


static func label(text: String, size: int = FONT_BODY, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node


static func wrap_label(text: String, size: int = FONT_BODY, color: Color = TEXT) -> Label:
	var node := label(text, size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func title(text: String, color: Color = ACCENT) -> Label:
	var node := label(text, FONT_TITLE, color)
	return node


static func button(text: String, min_width: int = 0) -> Button:
	var node := Button.new()
	node.text = text
	if min_width > 0:
		node.custom_minimum_size = Vector2(min_width, 30)
	return node


static func small_button(text: String, width: int = 40) -> Button:
	var node := button(text, width)
	node.custom_minimum_size = Vector2(width, 24)
	node.add_theme_font_size_override("font_size", FONT_SMALL)
	return node


static func vbox(separation: int = 6) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func hbox(separation: int = 6) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func spacer() -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func scroll(child: Control, min_height: int = 0) -> ScrollContainer:
	var node := ScrollContainer.new()
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if min_height > 0:
		node.custom_minimum_size = Vector2(0, min_height)
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_child(child)
	return node


## 速率统一显示两位小数（0.40 / 1.00），避免"0.4 和 0.4000001"这种抖动。
static func rate_text(value: float) -> String:
	return String.num(value, 2)


static func clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
