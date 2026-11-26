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
	# Window focus loss must pause, and focus regain must never auto-resume.
	controller._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	if not get_tree().paused or not controller.is_paused() or String(GameFlow.snapshot().get("pauseReason", "")) != "WINDOW_FOCUS_LOST":
		_fail_probe(controller, "window focus loss must enter the explicit focus-lost pause state")
		return
	controller._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	if not get_tree().paused or not controller.is_paused():
		_fail_probe(controller, "window focus regain must not resume combat automatically")
		return
	controller.set_paused(false)
	if get_tree().paused or controller.is_paused() or String(GameFlow.snapshot().get("battlePhase", "")) != "RUNNING":
		_fail_probe(controller, "focus-lost pause must require and accept explicit player resume")
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
	# A rejected scene path must restore the complete fault and pause state.
	get_tree().paused = true
	print("[SpaceBattlePauseControllerProbe] testing expected missing-scene rollback")
	if GameFlow.return_to_menu("res://scenes/menus/__missing_main_menu_probe__.tscn"):
		_fail_probe(controller, "missing main-menu scene must be rejected")
		return
	var rollback_snapshot := GameFlow.snapshot()
	if (
		not get_tree().paused
		or String(rollback_snapshot.get("battlePhase", "")) != "FAULTED"
		or String(rollback_snapshot.get("faultReason", "")) != "probe fault reason"
	):
		_fail_probe(controller, "failed menu transition must restore pause and fault registry state")
		return
	get_tree().paused = false
	print("[SpaceBattlePauseControllerProbe] expected-transition-rejection=passed")
	# Exercise the real fault-exit action, not only the abstract state transitions.
	# This probe is still inside _ready(); wait until SceneTree has completed the
	# current add-child/ready traversal before replacing the active scene. A normal
	# player button press arrives in a later input callback, after this phase.
	await get_tree().process_frame
	# SceneTree.change_scene_to_file() replaces this probe's owning scene. Keep a
	# direct SceneTree reference before invoking the controller; this Node and its
	# controller are expected to be detached/freed after a successful transition.
	var scene_tree: SceneTree = get_tree()
	controller._on_primary_action()
	var menu_snapshot := GameFlow.snapshot()
	if (
		scene_tree.paused
		or String(menu_snapshot.get("screen", "")) != "MENU"
		or String(menu_snapshot.get("battlePhase", "")) != "INACTIVE"
	):
		# Do not call get_tree() or inspect the old controller here: on successful
		# scene replacement, this probe node no longer belongs to a SceneTree.
		push_error("[SpaceBattlePauseControllerProbe] fault exit did not complete an unpaused MainMenu transition")
		return
	print("[SpaceBattlePauseControllerProbe] passed real-main-menu-transition=true")

func _fail_probe(controller: SpaceBattlePauseController, reason: String) -> void:
	get_tree().paused = false
	GameFlow.end_battle()
	GameFlow.enter_screen(GameFlow.Screen.MENU)
	push_error("[SpaceBattlePauseControllerProbe] " + reason)
	controller.queue_free()