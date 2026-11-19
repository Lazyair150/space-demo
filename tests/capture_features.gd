extends SceneTree
# 能力外观取证：能量盾、穿透弹、双发（需要真实窗口，headless 是 dummy 渲染器）
# 用法：godot.exe --path . --script res://tests/capture_features.gd

func _initialize() -> void:
	call_deferred("_run")

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png("res://tmp/ui_capture/%s.png" % name)
	print("[capture] ", name)

func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	var gs = get_root().get_node_or_null("GameState")
	if gs == null:
		gs = load("res://globals/GameState.gd").new()
		gs.name = "GameState"
		get_root().add_child(gs)
	if "persist_wallet" in gs:
		gs.persist_wallet = false
	gs.ore = 0
	gs.materials = 0
	gs.attack_level = 0

	var game = load("res://scenes/game/Game.tscn").instantiate()
	get_root().add_child(game)
	await create_timer(1.2).timeout

	var player = get_root().get_node_or_null("Game/Player")
	if player == null:
		for node in get_nodes_in_group("player"):
			player = node
	if player == null:
		print("[capture] 没找到玩家")
		quit(1)
		return

	var features = player.get_node("PlayerFeatures")
	# 三件能力都打开：盾看得见、子弹带穿透色、双发会多一颗
	features.set_feature_active(&"shield", true)
	features.set_feature_active(&"pierce", true)
	features.set_feature_active(&"double_shot", true)
	player.spawn_bullet()
	await create_timer(0.25).timeout
	await _shot("features_01_all")

	# 只留盾，拍一张干净的护盾外观
	features.set_feature_active(&"pierce", false)
	features.set_feature_active(&"double_shot", false)
	await create_timer(0.2).timeout
	await _shot("features_02_shield")

	game.queue_free()
	await create_timer(0.3).timeout
	gs.ore = 0
	gs.materials = 0
	gs.attack_level = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	quit(0)
