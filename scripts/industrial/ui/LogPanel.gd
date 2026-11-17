extends PanelContainer
## 记录栏（过程可见）。
##
## 数据源只有一个：运行时从 Bridge 取出的**表现层帧流**，每帧自带该时刻的过程日志快照。
## 不要在推进一步之后单独去查 `getSteps`：一次 tick 里过程往往整个结算完，
## 主体映射已被淘汰，那时查到的空数组意思是"没有保留的步骤"，不是"没发生过"（见 02 号文档 §9）。
##
## 这里只做措辞与排序，不做任何判断 —— 哪一步做了什么由 Core 说。

const UiKit := preload("res://scripts/industrial/ui/UiKit.gd")

## 界面保留的最大行数（超出的从最旧开始丢；丢了就在顶部留一句说明）。
const MAX_LINES := 300

var _built := false
var _text: RichTextLabel
var _note: Label
var _lines: Array[String] = []
var _seen_steps := {}
var _seen_frames := {}


func _ready() -> void:
	if _built:
		return
	_built = true
	var box := UiKit.vbox(6)
	add_child(box)

	var head := UiKit.hbox(8)
	head.add_child(UiKit.title("记录"))
	head.add_child(UiKit.spacer())
	var clear_button := UiKit.small_button("清空", 56)
	clear_button.pressed.connect(clear)
	head.add_child(clear_button)
	box.add_child(head)

	_note = UiKit.label("", UiKit.FONT_SMALL, UiKit.MUTED)
	box.add_child(_note)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = false
	_text.scroll_following = true
	_text.custom_minimum_size = Vector2(0, 150)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", UiKit.FONT_SMALL)
	_text.add_theme_color_override("default_color", UiKit.TEXT)
	box.add_child(_text)


## 追加一批帧。`dropped` > 0 表示 Core 侧缓冲裁剪过，必须说出来。
func append_frames(frames: Array, dropped: int) -> void:
	if not _built:
		_ready()

	var added := false
	for frame in frames:
		var frame_seq := int(frame.get("seq", -1))
		if frame_seq >= 0:
			if _seen_frames.has(frame_seq):
				continue
			_seen_frames[frame_seq] = true

		var steps: Array = frame.get("steps", [])
		if steps.is_empty():
			continue
		var op := str(frame.get("op", ""))
		var tick := int(frame.get("tick", 0))
		if op != "":
			_lines.append(_muted("—— 第 %d 回合 · %s ——" % [tick, op]))
			added = true

		for step in steps:
			var step_seq := int(step.get("seq", -1))
			if step_seq >= 0:
				if _seen_steps.has(step_seq):
					continue
				_seen_steps[step_seq] = true
			_lines.append(_step_line(step))
			added = true

	if dropped > 0:
		_lines.insert(0, _warn("（有 %d 条更早的帧没有被保留）" % dropped))
		added = true

	if not added:
		return

	while _lines.size() > MAX_LINES:
		_lines.remove_at(0)
	_note.text = "" if _lines.size() < MAX_LINES else "行数已达上限，更早的记录已滚掉。"
	_text.text = "\n".join(_lines)


func clear() -> void:
	_lines.clear()
	_seen_steps.clear()
	_seen_frames.clear()
	_text.text = ""
	_note.text = ""


func line_count() -> int:
	return _lines.size()


## 收到过多少帧（帧不一定带过程步骤：纯生产推进的帧就没有步骤，那是正常的）。测试用。
func frame_count() -> int:
	return _seen_frames.size()


## 一行的样子：「第 3 步 · 圆舱 → 三角舱（消耗 1 份蜜）」；摘要优先，其次 operation。
func _step_line(step: Dictionary) -> String:
	var summary := str(step.get("summary", ""))
	if summary == "":
		summary = str(step.get("operation", ""))
	if summary == "":
		summary = str(step.get("kind", ""))
	var step_index := 0
	var raw_step_index = step.get("stepIndex", 0)
	if raw_step_index != null:
		step_index = int(raw_step_index)
	var tick := int(step.get("tick", 0))
	if step_index > 0:
		return "[color=#%s]第 %d 回合[/color]　第 %d 步 · %s" % [
			UiKit.MUTED.to_html(false), tick, step_index, summary
		]
	return "[color=#%s]第 %d 回合[/color]　%s" % [UiKit.MUTED.to_html(false), tick, summary]


func _muted(text: String) -> String:
	return "[color=#%s]%s[/color]" % [UiKit.MUTED.to_html(false), text]


func _warn(text: String) -> String:
	return "[color=#%s]%s[/color]" % [UiKit.WARN.to_html(false), text]
