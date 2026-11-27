extends Node

func _ready() -> void:
	GameFlow.call_deferred("request_scene_transition", GameFlow.Screen.MENU, "res://scenes/menus/MainMenu.tscn")
	
