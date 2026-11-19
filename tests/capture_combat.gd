extends SceneTree
# 截图：伤害飘字 + 敌人掉血。必须带窗口跑（headless 是 dummy 渲染器）。
#   godot.exe --path . --script res://tests/capture_combat.gd

const OUT_DIR := "res://tmp/ui_capture"

func _init() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, name])
	print("[capture] %s" % name)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	var game = load("res://scenes/game/Game.tscn").instantiate()
	get_root().add_child(game)
	await create_timer(1.5).timeout

	var arena: Node2D = game.get_node("Arena")
	var player: CharacterBody2D = arena.get_node("Player")
	var wallet = get_root().get_node_or_null("GameState")
	if wallet != null:
		wallet.ore = 0
		wallet.materials = 0
		wallet.attack_level = 0

	# 摆一个追兵在玩家附近，手动打它，让飘字出现在画面中央
	var chaser: CharacterBody2D = load("res://scenes/actors/EnemyChaser.tscn").instantiate()
	chaser.position = player.position + Vector2(150, -60)
	arena.add_child(chaser)
	chaser.set_physics_process(false)
	await create_timer(0.3).timeout

	# 给追兵多加几格血，避免这一下暴击直接打死它（打死了飘字会跟着节点一起消失）
	chaser.health.set_max(9, true)
	# 用暴击命中，截图里能同时看到"暴击"标记
	chaser.receive_damage(DamageInfo.make(2, &"bullet", player, null, chaser.global_position, true))
	await create_timer(0.12).timeout

	await _shot("combat_01_damage_number")

	# 玩家挨一下：无敌 + 飘字
	player.receive_damage(DamageInfo.make(1, &"contact", chaser, chaser, player.global_position))
	await create_timer(0.12).timeout
	await _shot("combat_02_player_hit")

	if wallet != null:
		wallet.ore = 0
		wallet.materials = 0
		wallet.attack_level = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	game.queue_free()
	await process_frame
	quit(0)
