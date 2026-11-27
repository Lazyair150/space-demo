extends Control

@onready var final_score: Label = $VBoxContainer/FinalScore
@onready var hight_score: Label = $VBoxContainer/HightScore
@onready var menu_button: Button = $VBoxContainer/MenuButton
@onready var retry_button: Button = $VBoxContainer/RetryButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameFlow.enter_screen(GameFlow.Screen.GAME_OVER)
	final_score.text = "Final Score: %d" % GameState.score
	hight_score.text = "High Score: %d" % GameState.high_score
	retry_button.custom_minimum_size = Vector2(320, 48)
	menu_button.custom_minimum_size = Vector2(320, 48)
	retry_button.focus_mode = Control.FOCUS_ALL
	menu_button.focus_mode = Control.FOCUS_ALL
	retry_button.pressed.connect(_on_retry)
	menu_button.pressed.connect(_on_menu)
	retry_button.grab_focus()
	await get_tree().process_frame
	_validate_interaction_geometry()

func _validate_interaction_geometry() -> void:
	var container := $VBoxContainer as Control
	var background := $ColorRect as ColorRect
	if background.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		push_error("[GameOver] Decorative background must ignore mouse input")
	if not container.get_global_rect().encloses(retry_button.get_global_rect()) or not container.get_global_rect().encloses(menu_button.get_global_rect()):
		push_error("[GameOver] Visible buttons extend outside their parent hit-test rectangle")
	else:
		print("[GameOver] input-geometry=valid buttons=2 focus=ready")

func _on_retry() -> void:
	print("[GameOver] action=retry-to-hangar")
	retry_button.disabled = true
	menu_button.disabled = true
	GameState.reset_run()
	if not GameFlow.request_scene_transition(GameFlow.Screen.HANGAR, "res://scenes/industrial/SpaceHangar.tscn"):
		retry_button.disabled = false
		menu_button.disabled = false
		push_error("[GameOver] Failed to return to Hangar")

func _on_menu() -> void:
	print("[GameOver] action=return-to-menu")
	retry_button.disabled = true
	menu_button.disabled = true
	if not GameFlow.request_scene_transition(GameFlow.Screen.MENU, "res://scenes/menus/MainMenu.tscn"):
		retry_button.disabled = false
		menu_button.disabled = false
		push_error("[GameOver] Failed to return to Main Menu")
