extends SceneTree
## 阶段 12：全链路验收（一次跑完整条闭环）。
##
## 菜单 → 工业舱（派单、推进、结算得材料）→ 强化攻击力 → 返回菜单
## → 战斗里子弹伤害真的变高、打碎残骸真的掉矿 → 退出重进仍接着上一局。
##
## 这不是单元测试：走的是真实场景切换（change_scene_to_file）与真实节点，
## 唯一"作弊"的两处已标注（跳进工业舱用的是菜单按钮的同名处理函数；战斗只实例化
## 玩家与残骸，不开整局刷怪）。

const SAVE_PATH := "user://industrial_save.json"
const WALLET_PATH := "user://player.cfg"

var _checks := 0
var _failed := 0
var _wallet: Node

func _initialize() -> void:
	_clean_files()
	await _ensure_autoloads()
	await _run()
	_clean_files()
	_finish()

func _ensure_autoloads() -> void:
	_wallet = get_root().get_node_or_null("GameState")
	_wallet.persist_wallet = false
	if _wallet == null:
		_wallet = load("res://globals/GameState.gd").new()
		_wallet.name = "GameState"
		get_root().add_child(_wallet)
	if get_root().get_node_or_null("IndustrialRuntime") == null:
		var rt = load("res://scripts/industrial/runtime/IndustrialRuntime.gd").new()
		rt.name = "IndustrialRuntime"
		rt.freeze_when_unfocused = false
		get_root().add_child(rt)
	await process_frame

func _run() -> void:
	# 1) 菜单 → 工业舱
	change_scene_to_file("res://scenes/menus/MainMenu.tscn")
	await process_frame
	await process_frame
	var menu := current_scene
	_check(menu != null and menu.name == "MainMenu", "从主菜单开始")
	var entry: Node = menu.get_node_or_null("ColorRect/VBoxContainer/IndustrialButton")
	_check(entry != null, "主菜单有「进入工业舱」按钮")
	entry.emit_signal("pressed")   # 走按钮自己的处理函数，不绕开界面
	await process_frame
	await process_frame
	await process_frame
	var industrial := current_scene
	_check(industrial != null and industrial.name == "IndustrialMain", "点按钮后进到工业舱")

	var runtime := get_root().get_node("IndustrialRuntime")
	_check(bool(runtime.running), "工业世界已装配（autoload 里）")

	# 2) 工业：派单 → 推进 → 结算 → 拿材料
	runtime.set_master(0)
	runtime.set_slave(1)
	for i in 4:
		runtime.advance_manual()
	runtime.create_order_from_template("双圆工单")
	runtime.check_all_feasibility()
	runtime.start_order(0)
	for i in 16:
		if not _has_executing_order(runtime):
			break
		runtime.advance_manual()
	await process_frame
	runtime._collect_rewards()
	_check(_wallet.materials >= 1, "工单结算后拿到强化材料（%d 张）" % int(_wallet.materials))
	_check(_has_success_order(runtime), "世界里确实有一张「成功」的工单")

	# 3) 强化攻击力（界面按钮 → 钱包）
	_wallet.add_material(3 - int(_wallet.materials))
	industrial._refresh_reward_bar()
	industrial._on_upgrade_attack_pressed()
	_check(int(_wallet.attack_level) == 1, "花材料升到攻击 Lv1")
	_check(int(_wallet.attack_damage()) == 2, "子弹伤害变成 2")

	# 4) 保存 → 返回菜单
	industrial._on_save_pressed()
	_check(FileAccess.file_exists(SAVE_PATH), "存档文件已生成")
	industrial._on_leave_pressed()
	await process_frame
	await process_frame
	_check(current_scene != null and current_scene.name == "MainMenu", "返回主菜单")

	# 5) 战斗侧：子弹伤害与掉矿
	var player: Node = load("res://scenes/actors/Player.tscn").instantiate()
	get_root().add_child(player)
	await process_frame
	var ore_before := int(_wallet.ore)
	player._shoot()
	await process_frame
	var bullet_damage := -1
	for child in get_root().get_children():
		if str(child.name).begins_with("PlayerBullet") and child.get("damage") != null:
			bullet_damage = int(child.get("damage"))
			child.queue_free()
			break
	_check(bullet_damage == 2, "战斗中发射的子弹伤害是 2（实际 %d）" % bullet_damage)

	var asteroid: Node = load("res://scenes/actors/Asteroid.tscn").instantiate()
	get_root().add_child(asteroid)
	await process_frame
	asteroid.take_damage(999)
	await process_frame
	_check(int(_wallet.ore) == ore_before + 1, "打碎残骸得到 1 矿石（%d → %d）" % [ore_before, int(_wallet.ore)])
	# 残骸自毁时会播爆炸音效；等它放完再退出，否则退出报告会多出"音效实例泄漏"的噪音。
	await create_timer(1.2).timeout
	for child in get_root().get_children():
		if str(child.name).begins_with("Explosion"):
			child.queue_free()
	player.queue_free()

	# 6) 退出重进：新运行时读档，回到同一局
	var used_before := int(runtime.get_state().get("turns", {}).get("used", -1))
	runtime.queue_free()
	await process_frame
	await process_frame
	var second: Node = load("res://scripts/industrial/runtime/IndustrialRuntime.gd").new()
	second.name = "IndustrialRuntime2"
	second.freeze_when_unfocused = false
	get_root().add_child(second)
	var loaded: Dictionary = second.ensure_started()
	_check(bool(loaded["success"]), "重新装配时读档成功（%s）" % loaded.get("message", ""))
	_check(int(second.get_state().get("turns", {}).get("used", -2)) == used_before,
		"回合数接着上一局（%d）" % used_before)
	_check(int(_wallet.attack_level) == 1, "攻击力等级读回来了")

	# 收尾：把测试自己造的节点都释放掉，别让退出时的泄漏警告盖住真问题。
	# 残骸在 take_damage 里已经自毁，这里只释放还活着的节点。
	if is_instance_valid(asteroid):
		asteroid.queue_free()
	if is_instance_valid(second):
		second.queue_free()
	await process_frame
	await process_frame

func _has_executing_order(runtime: Node) -> bool:
	for order in runtime.get_state().get("orders", []):
		if str(order.get("status", "")) == "执行中":
			return true
	return false

func _has_success_order(runtime: Node) -> bool:
	for order in runtime.get_state().get("orders", []):
		if str(order.get("status", "")) == "成功":
			return true
	return false

func _clean_files() -> void:
	for path in [SAVE_PATH, WALLET_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)

func _finish() -> void:
	print("=== %d 项检查，%d 项失败 ===" % [_checks, _failed])
	quit(0 if _failed == 0 else 1)
