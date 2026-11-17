extends SceneTree
## 阶段 8/9 的场景级验收：主菜单 → 工业舱 → 回主菜单，工业世界不丢、回合不回退。
## 这条链是真实 `change_scene_to_file`，不是 free()+instantiate 模拟。

var _checks := 0
var _fails := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_ensure_autoloads()
	var runtime := get_root().get_node("IndustrialRuntime")

	var menu_error := change_scene_to_file("res://scenes/menus/MainMenu.tscn")
	_check(menu_error == OK, "能切到主菜单（error=%d）" % menu_error)
	await process_frame
	await process_frame
	var menu := current_scene
	_check(menu != null and menu.name == "MainMenu", "主菜单已就位")
	var entry: Node = menu.get_node_or_null("ColorRect/VBoxContainer/IndustrialButton") if menu != null else null
	_check(entry != null, "主菜单上有「进入工业舱」按钮")
	if entry == null:
		_finish()
		return

	# 真按一下按钮：走它自己的 pressed 回调
	(entry as Button).pressed.emit()
	await process_frame
	await process_frame
	await process_frame
	var industrial := current_scene
	_check(industrial != null and industrial.name == "IndustrialMain", "切到了工业舱场景（当前 %s）" % (industrial.name if industrial != null else "<null>"))
	_check(runtime.running, "进工业舱时世界已装配")
	var used_before := _used(runtime)
	industrial._advance_button.pressed.emit()
	await process_frame
	_check(_used(runtime) == used_before + 1, "在工业舱里推进一回合（%d → %d）" % [used_before, _used(runtime)])

	# 回主菜单：工业世界应该躺在 autoload 里继续存在
	industrial._on_leave_pressed()
	await process_frame
	await process_frame
	_check(current_scene != null and current_scene.name == "MainMenu", "回到了主菜单")
	_check(runtime.running, "离开工业舱后世界仍存活")
	_check(_used(runtime) == used_before + 1, "回合数没有因为切场景回退（%d）" % _used(runtime))

	# 再进一次：看到的还是刚才那一局（注意旧场景的按钮已经随场景释放，必须重新取）
	var entry_again: Node = current_scene.get_node_or_null("ColorRect/VBoxContainer/IndustrialButton")
	_check(entry_again != null, "回到主菜单后入口按钮还在")
	if entry_again == null:
		_finish()
		return
	(entry_again as Button).pressed.emit()
	await process_frame
	await process_frame
	await process_frame
	_check(_used(runtime) == used_before + 1, "再次进入工业舱读到的还是同一局（%d）" % _used(runtime))

	# 战斗侧资源：打碎一块残骸应该真的往 GameState 里加矿石（阶段 9 的入口那一半）
	var gs := get_root().get_node("GameState")
	var ore_before := int(gs.ore)
	var asteroid: Node = load("res://scenes/actors/Asteroid.tscn").instantiate()
	get_root().add_child(asteroid)
	await process_frame
	asteroid.take_damage(999)
	await process_frame
	_check(int(gs.ore) == ore_before + 1, "打碎残骸后矿石 %d → %d" % [ore_before, int(gs.ore)])
	_finish()


func _ensure_autoloads() -> void:
	# 清掉上一次跑留下的玩家存档：否则钱包/工业存档会把断言带偏（实测踩过）。
	for path in ["user://player.cfg", "user://industrial_save.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not get_root().has_node("GameState"):
		var gs = load("res://globals/GameState.gd").new()
		gs.name = "GameState"
		get_root().add_child(gs)
		# --script 环境也可能装载 autoload：无条件关闭钱包落盘，避免污染玩家存档
		gs.persist_wallet = false
	if not get_root().has_node("IndustrialRuntime"):
		var rt = load("res://scripts/industrial/runtime/IndustrialRuntime.gd").new()
		rt.name = "IndustrialRuntime"
		rt.freeze_when_unfocused = false
		get_root().add_child(rt)


func _used(runtime: Node) -> int:
	return int(runtime.get_state().get("turns", {}).get("used", -1))


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _finish() -> void:
	print("=== %d 项检查，%d 项失败 ===" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
