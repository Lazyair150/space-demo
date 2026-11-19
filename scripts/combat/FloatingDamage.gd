extends Node2D
# 命中飘字：只读 DamageResult，不改任何状态。
# 用 Node2D + draw_string 而不是 Label：
# Control 作为 Node2D 子节点时布局/可见性都依赖容器，实战里出现过"节点在、画面上没有"，
# 这里只需要"在世界坐标处画一行字"，用 _draw 最直接。
#
# 由角色在 DamageReceiver.resolved 里创建，挂在 Arena 下。

const RISE := 58.0
const LIFE := 0.8
const FONT_SIZE := 32

var _text := ""
var _color := Color(1, 1, 1)
var _font_size := FONT_SIZE
var _font: Font

func show_result(result: DamageResult) -> void:
	_text = "-%d" % result.hp_damage
	if result.absorbed > 0:
		_text = "挡 %d" % result.absorbed
	if result.critical:
		_text += " 暴击"
		font_size_hint(result)
	_color = _color_for(result)
	_font = ThemeDB.fallback_font
	z_index = 10
	queue_redraw()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - RISE, LIFE)
	tween.tween_property(self, "modulate:a", 0.0, LIFE).set_delay(LIFE * 0.5)
	tween.chain().tween_callback(queue_free)

func font_size_hint(result: DamageResult) -> void:
	_font_size = FONT_SIZE + 8

func _draw() -> void:
	if _font == null or _text.is_empty():
		return
	var width := _font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x
	var origin := Vector2(-width * 0.5, -14.0)
	# 深色描边：太空背景很暗，没有描边会糊在一起
	draw_string_outline(_font, origin, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, 8, Color(0.03, 0.04, 0.07, 1.0))
	draw_string(_font, origin, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, _color)

func _color_for(result: DamageResult) -> Color:
	if result.critical:
		return Color(1.0, 0.82, 0.36)
	if result.absorbed > 0 and result.hp_damage == 0:
		return Color(0.72, 0.92, 1.0)
	if result.hp_damage > 0:
		return Color(1.0, 0.72, 0.42)
	return Color(0.85, 0.85, 0.9)
