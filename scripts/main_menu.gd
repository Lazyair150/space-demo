extends Control

@onready var title: Label = $ColorRect/VBoxContainer/Title
@onready var high_score: Label = $ColorRect/VBoxContainer/HighScore
@onready var start_button: Button = $ColorRect/VBoxContainer/StartButton
@onready var quit_button: Button = $ColorRect/VBoxContainer/QuitButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameFlow.enter_screen(GameFlow.Screen.MENU)
	high_score.text = "High Score: %d" % GameState.high_score
	start_button.custom_minimum_size = Vector2(320, 48)
	quit_button.custom_minimum_size = Vector2(320, 48)
	start_button.focus_mode = Control.FOCUS_ALL
	quit_button.focus_mode = Control.FOCUS_ALL
	start_button.pressed.connect(_on_start)
	quit_button.pressed.connect(_on_quit)
	start_button.grab_focus()
	await get_tree().process_frame
	var menu_container := $ColorRect/VBoxContainer as Control
	if not menu_container.get_global_rect().encloses(start_button.get_global_rect()) or not menu_container.get_global_rect().encloses(quit_button.get_global_rect()):
		push_error("[MainMenu] Visible buttons extend outside their parent hit-test rectangle")
	else:
		print("[MainMenu] input-geometry=valid buttons=2 focus=ready")

func _on_start() -> void:
	start_button.disabled = true
	quit_button.disabled = true
	GameState.reset_run()
	if not GameFlow.request_scene_transition(GameFlow.Screen.HANGAR, "res://scenes/industrial/SpaceHangar.tscn"):
		start_button.disabled = false
		quit_button.disabled = false
		push_error("[MainMenu] Failed to open Hangar")
	
func _on_quit() -> void:
	start_button.disabled = true
	quit_button.disabled = true
	print("[MainMenu] action=quit")
	get_tree().quit()
