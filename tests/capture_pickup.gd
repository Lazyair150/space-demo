extends SceneTree
# 截图：战斗内胶囊 + HUD 效果条。必须带窗口跑（headless 是 dummy 渲染器，抓出来全黑）。
#   godot.exe --path . --script res://tests/capture_pickup.gd

const OUT_DIR := "res://tmp/ui_capture"
const PICKUP_SCENE := "res://scenes/pickups/BuffPickup.tscn"
const HASTE := "res://data/effects/haste.tres"

func _init() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	print("[capture] %s" % name)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))

	var game = load("res://scenes/game/Game.tscn").instantiate()
	get_root().add_child(game)
	await create_timer(1.6).timeout

	var wallet = get_root().get_node_or_null("GameState")
	if wallet != null:
		wallet.ore = 0
		wallet.materials = 0
		wallet.attack_level = 0

	var arena: Node2D = game.get_node("Arena")
	var player: CharacterBody2D = arena.get_node("Player")

	var pickup: Area2D = load(PICKUP_SCENE).instantiate()
	pickup.set("buff_definition", load(HASTE))
	pickup.set("tint", Color(0.55, 0.9, 1.0))
	pickup.position = player.position + Vector2(150, -40)
	arena.add_child(pickup)
	await create_timer(0.4).timeout
	await _shot("pickup_01_capsule")

	# 让玩家走过去吃：位置对齐后等物理帧触发 body_entered
	player.global_position = pickup.global_position
	await create_timer(0.5).timeout
	await _shot("pickup_02_haste")

	if wallet != null:
		wallet.ore = 0
		wallet.materials = 0
		wallet.attack_level = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	game.queue_free()
	await process_frame
	quit(0)
