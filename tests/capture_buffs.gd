extends SceneTree
# 截图：瞄准辅助 + 生命汲取 同时存在时的 HUD 与命中反馈。必须带窗口跑（headless 是 dummy 渲染器）。

var _root: Node
var _shots := 0

func _init() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	image.save_png("res://tmp/ui_capture/%s.png" % name)
	_shots += 1
	print("[capture] %s" % name)

func _run() -> void:
	if get_root().get_node_or_null("GameState") == null:
		var gs = load("res://globals/GameState.gd").new()
		gs.name = "GameState"
		get_root().add_child(gs)
	get_root().get_node("GameState").persist_wallet = false
	get_root().get_node("GameState").ore = 0
	get_root().get_node("GameState").materials = 0
	get_root().get_node("GameState").attack_level = 0

	var game = load("res://scenes/game/Game.tscn").instantiate()
	get_root().add_child(game)
	await create_timer(1.2).timeout

	var player = game.get_node_or_null("Arena/Player")
	var arena = game.get_node_or_null("Arena")
	if player == null or arena == null:
		print("[capture] 找不到玩家/场地")
		quit(1)
		return

	# 两个 Buff 同时挂上
	player.effects.apply(load("res://data/effects/aim_assist.tres"), player, -1.0)
	player.effects.apply(load("res://data/effects/lifesteal.tres"), player, -1.0)
	await create_timer(0.4).timeout

	# 摆一个能挨打的追兵，打两下让飘字和回血都出现
	var chaser = load("res://scenes/actors/EnemyChaser.tscn").instantiate()
	chaser.position = player.position + Vector2(150, -40)
	arena.add_child(chaser)
	chaser.set_physics_process(false)
	chaser.health.set_max(30, true)
	await create_timer(0.2).timeout
	player.health.current = 2
	for i in range(2):
		chaser.receive_damage(DamageInfo.make(4, &"bullet", player, null, chaser.global_position, true))
		await create_timer(0.1).timeout

	await _shot("buffs_01_hud")

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	game.queue_free()
	await process_frame
	quit(0)
