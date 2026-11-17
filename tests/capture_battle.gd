extends SceneTree
## 战斗 HUD 截图（需要真实窗口；headless 是 dummy 渲染器，抓出来是黑的）。
## 用法：godot.exe --path . --script res://tests/industrial/../capture_battle.gd

var _out_dir := "res://tmp/ui_capture"

func _init() -> void:
	call_deferred("_run")

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out_dir, name])
	print("[capture] ", name)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))

	# 截图从干净钱包开始，结束后复原，避免影响玩家真实进度
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	var wallet = get_root().get_node_or_null("GameState")
	if wallet != null:
		wallet.ore = 0
		wallet.materials = 0
		wallet.attack_level = 0

	var game = load("res://scenes/game/Game.tscn").instantiate()
	get_root().add_child(game)
	await process_frame
	await create_timer(1.6).timeout
	await _shot("battle_01_start")

	# 模拟刚打碎两块残骸 + 工单结算一张材料：看提示与目标行是否出现
	var gs = get_root().get_node_or_null("GameState")
	if gs != null:
		gs.add_ore(2)
	await process_frame
	await create_timer(0.2).timeout
	await _shot("battle_02_ore")

	if gs != null:
		gs.add_material(1)
	await process_frame
	await create_timer(0.2).timeout
	await _shot("battle_03_material")

	game.queue_free()
	await process_frame
	if gs != null:
		gs.ore = 0
		gs.materials = 0
		gs.attack_level = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	quit(0)
