extends CanvasLayer


@onready var score_label: Label = %Score
@onready var wave_label: Label = %Wave
@onready var hearts: HBoxContainer = $Root/TopRight/Hearts

@export var heart_texture:Texture2D

## 获得提示（拾取矿石/结算材料时浮出的一句话）与目标提示（下一步该做什么）。
## 参考 tiny-wizard 的做法：奖励要立刻看得见，且要告诉玩家"攒它干什么"。
const GAIN_COLOR := Color(0.941, 0.706, 0.353)
const HINT_COLOR := Color(0.549, 0.573, 0.651)

var _gain_label: Label
var _hint_label: Label
var _gain_tween: Tween
var _last_ore := 0
var _last_materials := 0

func _ready() -> void:
	_build_reward_ui()
	_last_ore = GameState.ore
	_last_materials = GameState.materials
	GameState.score_changed.connect(_on_score_changed)
	GameState.wave_changed.connect(_on_wave_changed)
	GameState.segment_changed.connect(_on_segment_changed)
	GameState.player_hp_changed.connect(_on_hp_changed)
	GameState.ore_changed.connect(_on_ore_changed)
	GameState.materials_changed.connect(_on_materials_changed)
	GameState.attack_changed.connect(_on_attack_changed)
	_on_score_changed(GameState.score)
	_on_ore_changed(GameState.ore)
	_on_wave_changed(GameState.wave)
	_on_hp_changed(3)
	_refresh_objective()

## 运行时搭两块提示，避免改动已有的 Hud.tscn 布局。
func _build_reward_ui() -> void:
	var root:=get_node_or_null("Root") as Control
	if root == null:
		return
	_gain_label = Label.new()
	_gain_label.name = "GainToast"
	_gain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gain_label.add_theme_font_size_override("font_size", 24)
	_gain_label.add_theme_color_override("font_color", GAIN_COLOR)
	_gain_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_gain_label.offset_top = 74.0
	_gain_label.offset_left = -240.0
	_gain_label.offset_right = 240.0
	_gain_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gain_label.modulate = Color(1, 1, 1, 0)
	root.add_child(_gain_label)

	_hint_label = Label.new()
	_hint_label.name = "ObjectiveHint"
	_hint_label.add_theme_font_size_override("font_size", 18)
	_hint_label.add_theme_color_override("font_color", HINT_COLOR)
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint_label.offset_left = 20.0
	_hint_label.offset_top = -34.0
	_hint_label.offset_right = 1000.0
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint_label)

func _show_gain(text: String) -> void:
	if _gain_label == null:
		return
	_gain_label.text = text
	_gain_label.modulate = Color(GAIN_COLOR.r, GAIN_COLOR.g, GAIN_COLOR.b, 1.0)
	if _gain_tween != null and _gain_tween.is_valid():
		_gain_tween.kill()
	_gain_tween = create_tween()
	_gain_tween.tween_interval(0.7)
	_gain_tween.tween_property(_gain_label, "modulate:a", 0.0, 0.9)

## 目标提示：把"矿石去哪花、材料攒到多少能升级"说清楚。
func _refresh_objective() -> void:
	if _hint_label == null:
		return
	var parts: Array[String] = []
	if GameState.attack_level >= GameState.MAX_ATTACK_LEVEL:
		parts.append("攻击已满级（%d 点）" % GameState.attack_damage())
	elif GameState.materials >= GameState.ATTACK_COST:
		parts.append("材料够了：去工业舱升级攻击")
	else:
		parts.append("再攒 %d 材料可升级攻击（工业舱工单结算）" % (GameState.ATTACK_COST - GameState.materials))
	if GameState.ore > 0:
		parts.append("矿石 %d：可投矿提速产线" % GameState.ore)
	_hint_label.text = "　·　".join(parts)
	
func _on_score_changed(s:int)->void:
	_update_score_text(s, GameState.ore)

func _on_ore_changed(amount:int)->void:
	_update_score_text(GameState.score, amount)
	if amount > _last_ore:
		_show_gain("+%d 矿石" % (amount - _last_ore))
	_last_ore = amount
	_refresh_objective()

func _on_materials_changed(amount:int)->void:
	if amount > _last_materials:
		_show_gain("+%d 强化材料" % (amount - _last_materials))
	_last_materials = amount
	_refresh_objective()

func _on_attack_changed(level:int, damage:int)->void:
	_refresh_objective()

func _update_score_text(s:int, amount:int)->void:
	# 顺带显示攻击力：工业舱产出的产品换来的强化材料，最终体现在这个数（子弹伤害）上。
	score_label.text ="Score:%d   矿石:%d   攻击:%d" % [s, amount, GameState.attack_damage()]

func _on_wave_changed(w:int)->void:
	_refresh_wave_text()

## 段落变化时刷新波次行；精英段与喘息段各给一句话，让玩家知道"现在该干什么"。
func _on_segment_changed(label:String, wave:int)->void:
	_refresh_wave_text()
	if label == "精英":
		_show_gain("精英波：一只强化敌机")
	elif label == "喘息":
		_show_gain("喘息：整理一下，或去工业舱")

func _refresh_wave_text()->void:
	if wave_label == null:
		return
	var segment :=GameState.segment
	if segment.is_empty():
		wave_label.text ="Wave:%d" % GameState.wave
		return
	wave_label.text ="Wave:%d   %s" % [GameState.wave, segment]
	var elite :=segment == "精英"
	wave_label.add_theme_color_override("font_color", Color(0.92, 0.42, 0.42) if elite else Color(1, 1, 1))

func _on_hp_changed(hp:int)->void:
	for c in hearts.get_children():
		c.queue_free()
	for i in hp:
		var heart_rect:=TextureRect.new()
		heart_rect.texture=heart_texture
		heart_rect.custom_maximum_size=Vector2(36,36)
		heart_rect.expand_mode=TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		heart_rect.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hearts.add_child(heart_rect)
		
