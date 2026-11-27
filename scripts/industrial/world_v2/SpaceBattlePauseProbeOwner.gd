extends Node
## Minimal root-level owner used only by SpaceBattlePauseControllerProbe.
## It mirrors the screen-transition + self-disposal contract of Game.gd without
## initializing World V2 Host, a player, or any combat actors.

func end_battle_for_menu() -> bool:
	if not GameFlow.return_to_menu("res://scenes/menus/MainMenu.tscn"):
		return false
	queue_free()
	return true
