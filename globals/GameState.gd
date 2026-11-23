extends Node

signal score_changed(new_score:int)
signal wave_changed(new_wave:int)
signal player_hp_changed(hp:int)
signal ore_changed(amount:int)
signal game_over_requested
signal materials_changed(amount:int)
signal attack_changed(level:int, damage:int)
signal segment_changed(label:String, wave:int)

const SAVE_PATH:="user://highscore.cfg"
## 玩家钱包（矿石/材料/攻击力）的落盘位置。与最高分分开存：钱包是玩法进度，最高分是成绩。
const WALLET_PATH:="user://player.cfg"
## 测试开关：自动化测试会把钱包改来改去，若照常落盘就会污染玩家真实存档。
## 测试脚本拿到 GameState 后把它设为 false。
var persist_wallet :=true

var score:int=0
var wave:int=0
## 当前段落名（参考 tiny-wizard 的"房间节奏"：每个段落回答一个问题）。
var segment:String=""
var high_score:int =0

## 工业舱工单结算得来的强化材料：用来提升舰船攻击力。
var materials:int = 0
## 攻击力等级：每级 +1 点子弹伤害；0 级就是基础伤害。
var attack_level:int = 0

## 每升一级攻击力要花多少强化材料，以及上限。
const ATTACK_COST := 3
const MAX_ATTACK_LEVEL := 5
## 基础子弹伤害（0 级时的伤害）。
const BASE_DAMAGE := 1

# 战斗里打碎残骸得到的矿石：投入工业舱的产线提速用。跨战斗累积，不随 reset_run 清零。
var ore:int =0

func _ready() -> void:
	_load_high_score()
	load_wallet()

## 退出时落盘（autoload 退出树时触发一次）。
func _exit_tree()->void:
	save_wallet()


func _load_high_score()->void:
	var cfg:=ConfigFile.new()
	if cfg.load(SAVE_PATH)==OK:
		high_score=int(cfg.get_value("score","high",0))
		print("get score")
	else :
		print("no scorefile")
	
func reset_run()->void:
	score =0
	wave =0
	segment =""
	score_changed.emit(score)
	wave_changed.emit(wave)
	segment_changed.emit(segment, wave)

## Transient run state is distinct from the persistent wallet/high-score files.
## It is captured with the Jar/Space battle checkpoint when resuming an active run.
func capture_run_state() -> Dictionary:
	return {
		"schemaVersion": 1,
		"score": score,
		"wave": wave,
		"segment": segment
	}

func restore_run_state(state: Dictionary) -> bool:
	if int(state.get("schemaVersion", 0)) != 1:
		return false
	var raw_score: Variant = state.get("score", null)
	var raw_wave: Variant = state.get("wave", null)
	var raw_segment: Variant = state.get("segment", null)
	if typeof(raw_score) != TYPE_INT or int(raw_score) < 0:
		return false
	if typeof(raw_wave) != TYPE_INT or int(raw_wave) < 0:
		return false
	if typeof(raw_segment) != TYPE_STRING or not ["", "热身", "压力", "精英", "喘息"].has(String(raw_segment)):
		return false
	if int(raw_wave) == 0 and not String(raw_segment).is_empty():
		return false
	score = int(raw_score)
	wave = int(raw_wave)
	segment = String(raw_segment)
	score_changed.emit(score)
	wave_changed.emit(wave)
	segment_changed.emit(segment, wave)
	return true

## 当前战斗段落名（热身/压力/精英/喘息）。由 Spawner 每波开始时设置，
## HUD 只负责显示——段落属于战斗节奏数据，不放在界面里。
func set_segment(label:String)->void:
	segment =label
	segment_changed.emit(segment, wave)

func add_ore(amount:int)->void:
	if amount <= 0:
		return
	ore += amount
	ore_changed.emit(ore)

func spend_ore(amount:int)->bool:
	if amount <= 0:
		return false
	if ore < amount:
		return false
	ore -= amount
	ore_changed.emit(ore)
	return true

## 工单结算发奖：调用方负责保证"同一张工单只发一次"（账本在 IndustrialRuntime 里）。
func add_material(amount:int)->void:
	if amount <= 0:
		return
	materials += amount
	materials_changed.emit(materials)

## 当前子弹伤害：基础伤害 + 攻击力等级。
func attack_damage()->int:
	return BASE_DAMAGE + attack_level

## 花材料升一级攻击力。材料不够或已到顶返回 false，且不改动任何数值。
func upgrade_attack()->bool:
	if attack_level >= MAX_ATTACK_LEVEL:
		return false
	if materials < ATTACK_COST:
		return false
	materials -= ATTACK_COST
	attack_level += 1
	materials_changed.emit(materials)
	attack_changed.emit(attack_level, attack_damage())
	return true

## 把钱包落到 user://player.cfg（矿石、强化材料、攻击力等级）。
func save_wallet()->void:
	if not persist_wallet:
		return
	# 无头运行只可能是自动化测试/CI：不写玩家存档，避免把测试数值带进真实进度。
	if DisplayServer.get_name() == "headless":
		return
	var cfg:=ConfigFile.new()
	cfg.set_value("wallet","ore",ore)
	cfg.set_value("wallet","materials",materials)
	cfg.set_value("wallet","attack_level",attack_level)
	cfg.save(WALLET_PATH)

## 读档；读不到或字段缺失就保持当前值（新玩家=全 0），不报错不弹窗。
func load_wallet()->void:
	var cfg:=ConfigFile.new()
	if cfg.load(WALLET_PATH)!=OK:
		return
	ore=max(0,int(cfg.get_value("wallet","ore",0)))
	materials=max(0,int(cfg.get_value("wallet","materials",0)))
	attack_level=clampi(int(cfg.get_value("wallet","attack_level",0)),0,MAX_ATTACK_LEVEL)
	ore_changed.emit(ore)
	materials_changed.emit(materials)
	attack_changed.emit(attack_level,attack_damage())

## 用存档里的数值覆盖钱包并广播（工业运行时读档时调用）。
func apply_wallet(data:Dictionary)->void:
	ore=max(0,int(data.get("ore",ore)))
	materials=max(0,int(data.get("materials",materials)))
	attack_level=clampi(int(data.get("attack_level",attack_level)),0,MAX_ATTACK_LEVEL)
	ore_changed.emit(ore)
	materials_changed.emit(materials)
	attack_changed.emit(attack_level,attack_damage())

func report_player_hp(hp:int)->void:
	player_hp_changed.emit(hp)

func add_score(amount:int)->void:
	score+=amount
	score_changed.emit(score)

func set_wave(new_wave:int)->void:
	wave=new_wave
	wave_changed.emit(wave)

func report_game_over()->void:
	if score>high_score:
		high_score=score
		_save_high_score()
	game_over_requested.emit()

func _save_high_score()->void:
	var cfg:=ConfigFile.new()
	cfg.set_value("score","high",high_score)
	cfg.save(SAVE_PATH)
