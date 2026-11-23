extends Control

@onready var final_score: Label = $VBoxContainer/FinalScore
@onready var hight_score: Label = $VBoxContainer/HightScore
@onready var menu_button: Button = $VBoxContainer/MenuButton
@onready var retry_button: Button = $VBoxContainer/RetryButton

func _ready() -> void:
	GameFlow.enter_screen(GameFlow.Screen.GAME_OVER)
	final_score.text="Final Score: %d"%GameState.score
	hight_score.text="High Score: %d"%GameState.high_score
	retry_button.pressed.connect(_on_retry)
	menu_button.pressed.connect(_on_menu)
	retry_button.grab_focus()

func _on_retry()->void:
	GameState.reset_run()
	GameFlow.request_scene_transition(GameFlow.Screen.BATTLE, "res://scenes/game/Game.tscn")

func _on_menu()->void:
	GameFlow.request_scene_transition(GameFlow.Screen.MENU, "res://scenes/menus/MainMenu.tscn")
