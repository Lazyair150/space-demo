extends SceneTree
## 战斗 HUD 的奖励反馈自测（不需要窗口，headless 可跑）。
## 依据：docs/design/07-tiny-wizard-对照与改造.md §3.1 —— 奖励要立刻看得见、且要说清攒它干什么。

var _checks := 0
var _fails := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("PASS ", what)
	else:
		_fails += 1
		print("FAIL ", what)

func _run() -> void:
	# --script 环境不装载 autoload，自己补一个钱包节点，并清掉落盘的钱包，避免上一轮测试的残留。
	var gs := get_root().get_node_or_null("GameState")
	if gs == null:
		gs = load("res://globals/GameState.gd").new()
		gs.name = "GameState"
		get_root().add_child(gs)
		# --script 环境也可能装载 autoload：无条件关闭钱包落盘，避免污染玩家存档
		gs.persist_wallet = false
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	gs.ore = 0
	gs.materials = 0
	gs.attack_level = 0
	gs.score = 0
	gs.wave = 0

	var hud = load("res://scenes/ui/HUD.tscn").instantiate()
	get_root().add_child(hud)
	await process_frame
	await process_frame

	_check(hud.get_node_or_null("Root/GainToast") != null, "HUD 有获得提示节点")
	_check(hud.get_node_or_null("Root/ObjectiveHint") != null, "HUD 有目标提示节点")

	var gain: Label = hud.get_node("Root/GainToast")
	var hint: Label = hud.get_node("Root/ObjectiveHint")
	_check(is_equal_approx(gain.modulate.a, 0.0), "开局没有获得提示（transparent）")
	_check(hint.text.contains("再攒 3 材料"), "开局目标提示：再攒 3 材料（实际：%s）" % hint.text)

	gs.add_ore(2)
	await process_frame
	_check(gain.text == "+2 矿石", "拾取 2 矿石时提示 +2 矿石（实际：%s）" % gain.text)
	_check(is_equal_approx(gain.modulate.a, 1.0), "提示可见")
	_check(hint.text.contains("矿石 2"), "目标提示反映矿石数量")

	gs.add_ore(1)
	await process_frame
	_check(gain.text == "+1 矿石", "再次拾取只报增量（实际：%s）" % gain.text)

	gs.add_material(1)
	await process_frame
	_check(gain.text == "+1 强化材料", "工单结算提示 +1 强化材料（实际：%s）" % gain.text)
	_check(hint.text.contains("再攒 2 材料"), "材料 1 时提示再攒 2（实际：%s）" % hint.text)

	gs.add_material(2)
	await process_frame
	_check(hint.text.contains("材料够了"), "材料 3 时提示可以升级（实际：%s）" % hint.text)

	gs.attack_level = gs.MAX_ATTACK_LEVEL
	gs.attack_changed.emit(gs.attack_level, gs.attack_damage())
	await process_frame
	_check(hint.text.contains("攻击已满级"), "满级后提示攻击已满级（实际：%s）" % hint.text)

	gs.add_score(5)
	gs.set_wave(3)
	await process_frame
	var score_label: Label = hud.get_node("Root/HBoxContainer/Score")
	var wave_label: Label = hud.get_node("Root/HBoxContainer/Wave")
	_check(score_label.text.contains("Score:5"), "分数行仍然更新（实际：%s）" % score_label.text)
	_check(score_label.text.contains("攻击:6"), "分数行显示攻击力（实际：%s）" % score_label.text)
	_check(wave_label.text == "Wave:3", "波次行仍然更新（实际：%s）" % wave_label.text)

	hud.queue_free()
	await process_frame
	# 测试不许污染玩家真实钱包：复原数值并删掉落盘文件
	gs.ore = 0
	gs.materials = 0
	gs.attack_level = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	print("=== %d 项检查，%d 项失败 ===" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
