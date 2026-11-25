extends Node
## Synthetic check for the combat pause gate. Does not initialize a battle or Jar world.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not GameFlow.begin_battle_preparation() or not GameFlow.mark_battle_running():
		push_error("[SpaceBattlePauseControllerProbe] could not establish a running battle state")
		return
	if GameFlow.begin_battle_preparation() or String(GameFlow.snapshot().get("battlePhase", "")) != "RUNNING":
		push_error("[SpaceBattlePauseControllerProbe] a second launch must not replace a running battle")
		GameFlow.end_battle()
		GameFlow.enter_screen(GameFlow.Screen.MENU)
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
	if not GameFlow.begin_battle_preparation() or not GameFlow.begin_battle_resuming() or not GameFlow.mark_battle_resume_ready():
		_fail_probe(controller, "restored battle must pass through RESUMING into RESUME_READY")
		return
	if String(GameFlow.snapshot().get("battlePhase", "")) != "RESUME_READY":
		_fail_probe(controller, "resume-ready state must be externally observable")
		return
	if not GameFlow.confirm_resume_battle() or String(GameFlow.snapshot().get("battlePhase", "")) != "RUNNING":
		_fail_probe(controller, "only explicit confirmation may authorize restored battle time")
		return
	GameFlow.end_battle()
	GameFlow.enter_screen(GameFlow.Screen.MENU)
	if not GameFlow.begin_battle_preparation() or not GameFlow.mark_battle_running() or not GameFlow.fault_battle("probe fault reason"):
		_fail_probe(controller, "runtime fault must latch from RUNNING")
		return
	controller.show_fault("probe fault reason")
	var fault_snapshot := GameFlow.snapshot()
	if String(fault_snapshot.get("battlePhase", "")) != "FAULTED" or String(fault_snapshot.get("faultReason", "")) != "probe fault reason" or int(fault_snapshot.get("lastCompletedWorldTimeMilli", -2)) != -1 or int(fault_snapshot.get("lastCompletedLogicalTimeMilli", -2)) != -1 or controller._paused or not controller._faulted or not controller._overlay.visible:
		_fail_probe(controller, "fault must be distinct from player death/pause and remain visible")
		return
	if controller._primary_button.text != "返回主菜单  /  Main Menu":
		_fail_probe(controller, "fault action must navigate to the main menu, not resume combat")
		return
	# Exercise the real fault-exit action, not only the abstract state transitions.
	# The probe intentionally changes to the actual main-menu scene as its final step.
	controller._on_primary_action()
	var menu_snapshot := GameFlow.snapshot()
	if (
		get_tree().paused
		or String(menu_snapshot.get("screen", "")) != "MENU"
		or String(menu_snapshot.get("battlePhase", "")) != "INACTIVE"
		or controller._overlay.visible
	):
		_fail_probe(controller, "fault exit must unpause, clear battle ownership, and hide the old overlay")
		return
	print("[SpaceBattlePauseControllerProbe] passed terminal-menu-transition=true")

func _fail_probe(controller: SpaceBattlePauseController, reason: String) -> void:
	get_tree().paused = false
	GameFlow.end_battle()
	GameFlow.enter_screen(GameFlow.Screen.MENU)
	push_error("[SpaceBattlePauseControllerProbe] " + reason)
	controller.queue_free()