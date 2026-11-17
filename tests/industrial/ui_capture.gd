extends SceneTree
## 把工业界面渲染成 PNG，用来做人工看图的依据（不是自动化视觉验收）。
##
## 必须带窗口跑（不能用 --headless：headless 是 dummy 渲染器，抓出来是全黑）。
## 只抓这个游戏自己的视口，不碰桌面。

const OUT_DIR := "res://tmp/ui_capture"


func _initialize() -> void:
	var runtime = get_root().get_node_or_null("IndustrialRuntime")
	if runtime == null:
		runtime = load("res://scripts/industrial/runtime/IndustrialRuntime.gd").new()
		runtime.name = "IndustrialRuntime"
		get_root().add_child(runtime)
	runtime.freeze_when_unfocused = false

	var packed: PackedScene = load("res://scenes/industrial/IndustrialMain.tscn")
	var scene: Control = packed.instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# 0) 给一点矿石，让「投矿」按钮处于可用态（矿石平时由战斗打残骸得来）
	if not get_root().has_node("GameState"):
		var created = load("res://globals/GameState.gd").new()
		created.name = "GameState"
		get_root().add_child(created)
	var wallet := get_root().get_node("GameState")
	wallet.persist_wallet = false
	wallet.add_ore(6)
	scene._apply_state(scene._state)

	# 1) 开局：空态
	await _shot("01_empty")

	# 2) 选主台（选择器打开的样子 → 选定后的样子）
	scene._on_picker_requested("master")
	await _shot("02_picker")
	scene._picker_list.select(0)
	scene._on_picker_confirm()
	runtime.set_slave(1)
	for i in range(3):
		runtime.advance_manual()
	await _shot("03_benches")

	# 3) 派单、看工单卡与做法；再开始一单，看执行进度与记录栏
	runtime.create_random_order()
	runtime.check_all_feasibility()
	await _shot("04_orders")
	for order in runtime.get_state().get("orders", []):
		var feasibility = order.get("feasibilityResult", null)
		if feasibility is Dictionary and bool((feasibility as Dictionary).get("feasible", false)):
			runtime.start_order(int(order.get("index", 0)))
			break
	for i in range(2):
		runtime.advance_manual()
	await _shot("05_running")

	# 4) 模板派单（阶段 7 新加的入口）：选择器里列的是世界配置的模板
	scene._on_order_action("templates", {})
	await _shot("06_templates")
	scene._picker_layer.hide()

	print("captured to ", ProjectSettings.globalize_path(OUT_DIR))
	quit(0)


func _shot(name_text: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name_text]
	var err := image.save_png(path)
	print("  shot ", path, " -> ", err)
	await process_frame
	await process_frame
