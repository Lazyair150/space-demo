extends Node
## Synthetic check for the combat pause gate. Does not initialize a battle or Jar world.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not GameFlow.begin_battle_preparation() or not GameFlow.mark_battle_running():
		push_error("[SpaceBattlePauseControllerProbe] could not establish a running battle state")
		return
	var controller := SpaceBattlePauseController.new()
	add_child(controller)
	if controller.process_mode != Node.PROCESS_MODE_ALWAYS:
		_fail_probe(controller, "pause controller must process while paused")
		return
	controller.set_paused(true, "probe")
	if not get_tree().paused or not controller.is_paused() or not controller._overlay.visible or String(GameFlow.snapshot().get("battlePhase", "")) != "PAUSED":
		_fail_probe(controller, "pause must freeze the SceneTree and show its always-process overlay")
		return
	controller.set_paused(false)
	if get_tree().paused or controller.is_paused() or controller._overlay.visible or String(GameFlow.snapshot().get("battlePhase", "")) != "RUNNING":
		_fail_probe(controller, "resume must release both pause gates and hide the overlay")
		return
	GameFlow.end_battle()
	GameFlow.enter_screen(GameFlow.Screen.MENU)
	print("[SpaceBattlePauseControllerProbe] passed")
	controller.queue_free()

func _fail_probe(controller: SpaceBattlePauseController, reason: String) -> void:
	get_tree().paused = false
	GameFlow.end_battle()
	GameFlow.enter_screen(GameFlow.Screen.MENU)
	push_error("[SpaceBattlePauseControllerProbe] " + reason)
	controller.queue_free()