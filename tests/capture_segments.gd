extends SceneTree
## 段落截图（需要真实窗口）：跑出「精英」「喘息」两波，看 HUD 上的段落行与提示。

var _out_dir := "res://tmp/ui_capture"

func _init() -> void:
	call_deferred("_run")

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("%s/%s.png" % [_out_dir, name])
	print("[capture] ", name)

func _kill_all() -> void:
	for e in get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			e.queue_free()
	await process_frame

func _wait_segment(label: String, max_seconds: float) -> bool:
	var gs := get_root().get_node_or_null("GameState")
	var deadline := Time.get_ticks_msec() + int(max_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if gs != null and String(gs.segment) == label:
			return true
		await create_timer(0.1).timeout
	return false

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	var gs := get_root().get_node_or_null("GameState")
	if gs != null:
		gs.ore = 0
		gs.materials = 0
		gs.attack_level = 0

	var game = load("res://scenes/game/Game.tscn").instantiate()
	get_root().add_child(game)
	await process_frame

	var spawner = game.get_node_or_null("Node")
	if spawner != null:
		spawner.wave_break_seconds = 0.4
		spawner.spawn_stagger_seconds = 0.05

	# 快速清掉前两波，跑到精英波
	var guard := 0
	while guard < 400:
		guard += 1
		if gs != null and String(gs.segment) == "精英":
			break
		await _kill_all()
		await create_timer(0.1).timeout

	if await _wait_segment("精英", 3.0):
		await create_timer(0.4).timeout
		await _shot("battle_04_elite")
	await _kill_all()

	if await _wait_segment("喘息", 6.0):
		await create_timer(0.3).timeout
		await _shot("battle_05_rest")

	game.queue_free()
	await process_frame
	if gs != null:
		gs.ore = 0
		gs.materials = 0
		gs.attack_level = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	quit(0)
