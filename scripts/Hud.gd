extends CanvasLayer


@onready var score_label: Label = %Score
@onready var wave_label: Label = %Wave
@onready var hearts: HBoxContainer = $Root/TopRight/Hearts

@export var heart_texture:Texture2D

func _ready() -> void:
	GameState.score_changed.connect(_on_score_changed)
	GameState.wave_changed.connect(_on_wave_changed)
	GameState.player_hp_changed.connect(_on_hp_changed)
	GameState.ore_changed.connect(_on_ore_changed)
	_on_score_changed(GameState.score)
	_on_ore_changed(GameState.ore)
	_on_wave_changed(GameState.wave)
	_on_hp_changed(3)
	
func _on_score_changed(s:int)->void:
	_update_score_text(s, GameState.ore)

func _on_ore_changed(amount:int)->void:
	_update_score_text(GameState.score, amount)

func _update_score_text(s:int, amount:int)->void:
	# 顺带显示攻击力：工业舱产出的产品换来的强化材料，最终体现在这个数（子弹伤害）上。
	score_label.text ="Score:%d   矿石:%d   攻击:%d" % [s, amount, GameState.attack_damage()]

func _on_wave_changed(w:int)->void:
	wave_label.text ="Wave:%d" %w

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
		
