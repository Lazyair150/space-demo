extends SceneTree
## 给 S2 的三张验证单留证据图（需要真实窗口，headless 是 dummy 渲染器会全黑）。
## 用法：godot.exe --path . --script res://tests/industrial/tradeoff_capture.gd

const WORLD_PATH := "res://data/industrial/world_tradeoff.json"
const OUT_DIR := "res://tmp/ui_capture"

var _runtime: Node
var _wallet: Node
var _scene: Node


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for path in ["user://player.cfg", "user://industrial_save.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	_wallet = get_root().get_node_or_null("GameState")
	if _wallet == null:
		_wallet = load("res://globals/GameState.gd").new()
		_wallet.name = "GameState"
		get_root().add_child(_wallet)
	_wallet.persist_wallet = false

	_runtime = get_root().get_node_or_null("IndustrialRuntime")
	if _runtime == null:
		_runtime = load("res://scripts/industrial/runtime/IndustrialRuntime.gd").new()
		_runtime.name = "IndustrialRuntime"
		get_root().add_child(_runtime)

	_runtime.start(WORLD_PATH, -1)
	_runtime.set_master(0)
	for i in 6:
		_runtime.advance_manual()
	for name in ["双线争料", "异形换台", "超长线"]:
		_runtime.create_order_from_template(name)
	_runtime.check_all_feasibility()

	_scene = load("res://scenes/industrial/IndustrialMain.tscn").instantiate()
	get_root().add_child(_scene)
	await process_frame
	_scene._apply_state(_runtime.get_state())
	await _shot("tradeoff_01_master_a")

	# 换成禁蜜的副台做主台：同一张「异形换台」从"要做一次改形"变成"无路径"
	_runtime.set_master(1)
	_runtime.check_all_feasibility()
	_scene._apply_state(_runtime.get_state())
	await _shot("tradeoff_02_master_b")

	_scene.queue_free()
	await process_frame
	_runtime.queue_free()
	_wallet.queue_free()
	await process_frame
	for path in ["user://player.cfg", "user://industrial_save.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit(0)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	print("  shot %s -> %d" % [path, image.save_png(path)])
