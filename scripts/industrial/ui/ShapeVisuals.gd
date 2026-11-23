extends RefCounted
## Presentation-only shape vocabulary. Never used by Jar rules, feasibility, or resource accounting.

const NEUTRAL := Color("9aa8b8")
const SHAPES := {
	"圆形舱段": {"color": Color("59b9e8"), "glyph": "●"},
	"圆罐": {"color": Color("59b9e8"), "glyph": "●"},
	"方形舱段": {"color": Color("e5b85f"), "glyph": "■"},
	"方罐": {"color": Color("e5b85f"), "glyph": "■"},
	"三棱舱段": {"color": Color("b69af7"), "glyph": "▲"},
	"长条舱段": {"color": Color("6fd1ae"), "glyph": "▬"},
}

static func color_for(shape: String) -> Color:
	if SHAPES.has(shape):
		return SHAPES[shape].color
	if "圆" in shape:
		return Color("59b9e8")
	if "方" in shape:
		return Color("e5b85f")
	if "三棱" in shape or "三角" in shape:
		return Color("b69af7")
	if "长条" in shape or "长形" in shape:
		return Color("6fd1ae")
	return NEUTRAL

static func glyph_for(shape: String) -> String:
	if SHAPES.has(shape):
		return SHAPES[shape].glyph
	if "圆" in shape:
		return "●"
	if "方" in shape:
		return "■"
	if "三棱" in shape or "三角" in shape:
		return "▲"
	if "长条" in shape or "长形" in shape:
		return "▬"
	return "◆"

static func blend_marks(base_marks: Array, additional_marks: Array) -> Color:
	var total := Color(0, 0, 0, 0)
	var weight := 0.0
	for mark in base_marks:
		total += color_for(String(mark)) * 2.0
		weight += 2.0
	for mark in additional_marks:
		total += color_for(String(mark))
		weight += 1.0
	return total / weight if weight > 0.0 else NEUTRAL

static func liquid_color_for(liquid: String) -> Color:
	match liquid:
		"酒":
			return Color("d96b7c")
		"蜜":
			return Color("e5b85f")
		_:
			return NEUTRAL

static func apply_meter_style(meter: ProgressBar, fill_color: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(4)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("263241")
	background.set_corner_radius_all(4)
	meter.add_theme_stylebox_override("fill", fill)
	meter.add_theme_stylebox_override("background", background)
