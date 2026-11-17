extends SceneTree
## 阶段 11 冒烟测试：存档 / 读档。
##
## 验证四件事：
## 1. 存档能落盘，读回来是同一个世界（回合、工单、仓库、主从台都不变）；
## 2. 玩家钱包（矿石/材料/攻击力）一起存、一起回；
## 3. 读档不等于"接着走"：累积器回到 0，不会一进来就补算；
## 4. 存档坏了不静默：退回新开一局，并把原因说出来。

const SAVE_PATH := "user://industrial_save.json"
const WALLET_PATH := "user://player.cfg"

var _checks := 0
var _failed := 0
var _wallet: Node

func _initialize() -> void:
	_clean_files()
	_boot_wallet()
	await process_frame
	await _run()
	_clean_files()
	_finish()

func _boot_wallet() -> void:
	if get_root().has_node("GameState"):
		_wallet = get_root().get_node("GameState")
	else:
		_wallet = load("res://globals/GameState.gd").new()
		_wallet.name = "GameState"
		get_root().add_child(_wallet)
		# --script 环境也可能装载 autoload：无条件关闭钱包落盘，避免污染玩家存档
		_wallet.persist_wallet = false

func _make_runtime(node_name: String) -> Node:
	var runtime: Node = load("res://scripts/industrial/runtime/IndustrialRuntime.gd").new()
	runtime.name = node_name
	runtime.auto_advance = false
	runtime.freeze_when_unfocused = false
	get_root().add_child(runtime)
	return runtime

func _run() -> void:
	var first := _make_runtime("RuntimeA")
	var started: Dictionary = first.ensure_started()
	_check(bool(started["success"]), "第一局装配成功（%s）" % started.get("message", ""))
	if not bool(started["success"]):
		return

	first.set_master(0)
	first.set_slave(1)
	for i in 4:
		first.advance_manual()
	first.create_order_from_template("双圆工单")
	first.check_all_feasibility()
	first.start_order(0)
	for i in 12:
		if not _has_executing_order(first):
			break
		first.advance_manual()
	first.advance_manual()

	var fingerprint: Dictionary = _fingerprint(first.get_state())
	_check(int(fingerprint["used"]) > 0, "存档前已经推进过回合（%d）" % int(fingerprint["used"]))
	_check(int(fingerprint["orders"]) >= 1, "存档前世界里有工单（%d 张）" % int(fingerprint["orders"]))

	_wallet.ore = 7
	_wallet.materials = 2
	_wallet.attack_level = 1

	var saved: Dictionary = first.save_game()
	_check(bool(saved["success"]), "存档成功（%s）" % saved.get("message", ""))
	_check(FileAccess.file_exists(SAVE_PATH), "存档文件已生成：%s" % SAVE_PATH)
	if not FileAccess.file_exists(SAVE_PATH):
		return

	# 模拟"关掉游戏再打开"：把运行时整个释放掉，再新建一个。
	first.free()
	await process_frame

	# 钱包先被清空，确认是"从存档读回来"的，不是内存里剩下的。
	_wallet.ore = 0
	_wallet.materials = 0
	_wallet.attack_level = 0

	var second := _make_runtime("RuntimeB")
	var loaded: Dictionary = second.ensure_started()
	_check(bool(loaded["success"]), "重新打开时读档成功（%s）" % loaded.get("message", ""))
	var restored: Dictionary = _fingerprint(second.get_state())
	_check(int(restored["used"]) == int(fingerprint["used"]),
		"回合数一致（%d → %d）" % [int(fingerprint["used"]), int(restored["used"])])
	_check(int(restored["orders"]) == int(fingerprint["orders"]),
		"工单数一致（%d → %d）" % [int(fingerprint["orders"]), int(restored["orders"])])
	_check(str(restored["orders_digest"]) == str(fingerprint["orders_digest"]),
		"工单状态逐条一致")
	_check(str(restored["warehouse_digest"]) == str(fingerprint["warehouse_digest"]),
		"仓库内容一致（含每种工质的数量）")
	_check(int(restored["master"]) == int(fingerprint["master"]), "主装配台还是同一台")
	_check(int(restored["slave"]) == int(fingerprint["slave"]), "副装配台还是同一台")

	_check(int(_wallet.ore) == 7, "矿石读回来了（%d）" % int(_wallet.ore))
	_check(int(_wallet.materials) == 2, "材料读回来了（%d）" % int(_wallet.materials))
	_check(int(_wallet.attack_level) == 1, "攻击力等级读回来了（%d）" % int(_wallet.attack_level))

	# 读档不是"接着走"：刚读回来时累积器是 0，喂半秒不该推进。
	var before_used := int(second.get_state().get("turns", {}).get("used", 0))
	second.step_wall_time(0.5)
	_check(int(second.get_state().get("turns", {}).get("used", 0)) == before_used,
		"读档后不会凭空补算（喂 0.5 秒不推进）")

	# 存档坏了：退回新开一局，并把原因带回来（不静默、不崩）。
	second.free()
	await process_frame
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()

	var third := _make_runtime("RuntimeC")
	var recovered: Dictionary = third.ensure_started()
	_check(bool(recovered["success"]), "存档损坏时仍能开新局")
	_check(str(recovered.get("message", "")).contains("存档没读成"),
		"存档损坏时把原因说出来了（「%s」）" % str(recovered.get("message", "")))
	_check(int(third.get_state().get("turns", {}).get("used", -1)) == 0, "退回的是全新一局（回合 0）")
	third.free()
	await process_frame

func _has_executing_order(runtime: Node) -> bool:
	for order in runtime.get_state().get("orders", []):
		if str(order.get("status", "")) == "执行中":
			return true
	return false

## 取"能代表世界身份"的几个字段，比较读档前后是否一致。
func _fingerprint(state: Dictionary) -> Dictionary:
	var turns: Dictionary = state.get("turns", {})
	var warehouse: Dictionary = state.get("warehouse", {})
	var global_state: Dictionary = state.get("globalState", {})
	var orders_digest := ""
	for order in state.get("orders", []):
		orders_digest += "%s:%s:%s|" % [str(order.get("id")), str(order.get("status")), str(order.get("type"))]
	var jar_count := int(warehouse.get("jars", 0))
	var liquids: Dictionary = warehouse.get("liquids", {})
	var warehouse_digest := "jars=%d" % jar_count
	var keys := liquids.keys()
	keys.sort()
	for key in keys:
		warehouse_digest += " %s=%s" % [str(key), str(liquids[key])]
	return {
		"used": int(turns.get("used", -1)),
		"orders": (state.get("orders", []) as Array).size(),
		"orders_digest": orders_digest,
		"warehouse_digest": warehouse_digest,
		"master": int(global_state.get("currentMaster")) if global_state.get("currentMaster") != null else -1,
		"slave": int(global_state.get("currentSlave")) if global_state.get("currentSlave") != null else -1,
	}

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
