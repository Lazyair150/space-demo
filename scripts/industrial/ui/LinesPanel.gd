extends PanelContainer
## 产线面板（原 `play.html` 的产线面板 + `production-view.js` 的"生产 ≠ 流入"说明）。
##
## 玩家在这里只做一件事：决定每条形状线每回合产几只。
## 刻意保留 Web 版的两条口径，因为它们防的是同一类误解：
## - "累加"决定这一回合是否真的落下一只（0.4/回合 不等于每回合 +1）；
## - "流入"是仓库→主台的搬运上限，与生产速率无关（液体自产为 0 也可能有货进入主台）。

signal rate_requested(producer_name: String, shape: String, rate: float)
signal liquid_rate_requested(liquid: String, rate: float)
## 投矿石把某条产线提高一档：界面只发意图，扣矿与推进由上层（持有 GameState 的一方）负责。
signal upgrade_requested(producer_name: String, shape: String, target_rate: float, cost: int)

## 一次投矿能买到的速率增量与花费；上限即世界配置允许的最高档。
const UPGRADE_STEP := 0.2
const UPGRADE_COST := 2
const MAX_RATE := 0.6

var _ore := 0

const UiKit := preload("res://scripts/industrial/ui/UiKit.gd")

## 与 Web 调试页一致的四个快捷档位；不在档位上的速率显示成"当前 x.xx"。
const RATES := [0.0, 0.2, 0.4, 0.6]

var _built := false
var _list: VBoxContainer
var _head_hint: Label


func _ready() -> void:
	if _built:
		return
	_built = true
	var box := UiKit.vbox(6)
	add_child(box)
	box.add_child(UiKit.title("产线"))
	_head_hint = UiKit.wrap_label("", UiKit.FONT_SMALL, UiKit.MUTED)
	box.add_child(_head_hint)
	_list = UiKit.vbox(8)
	box.add_child(UiKit.scroll(_list, 120))


func bind(status: Dictionary, ore: int = 0) -> void:
	if not _built:
		_ready()
	_ore = ore

	var slots: Dictionary = status.get("slots", {})
	var used := int(slots.get("used", 0))
	var limit := int(slots.get("limit", 0))
	_head_hint.text = "产线占用 %d / %s（0 表示不限）　·　流入另计" % [
		used, "不限" if limit <= 0 else str(limit)
	]

	UiKit.clear_children(_list)

	var producers: Array = status.get("producers", [])
	var generators: Array = status.get("generators", [])
	var idle: Array[String] = []

	for generator in generators:
		var shape := str(generator.get("shape", ""))
		var sources := _sources_for(producers, shape)
		if sources.is_empty():
			idle.append(shape)
			continue
		_list.add_child(_shape_card(generator, sources))

	if not idle.is_empty():
		_list.add_child(UiKit.wrap_label(
			"另有 %d 条形状线没有生产源，不参与每回合计算：%s" % [idle.size(), "、".join(idle)],
			UiKit.FONT_SMALL, UiKit.MUTED))

	# 工质：世界自产，不属于任何一个生产者，所以单独一格
	var liquid_rates: Dictionary = status.get("liquidRates", {})
	var accumulated: Dictionary = status.get("liquidAccumulated", {})
	var warehouse: Dictionary = status.get("warehouse", {})
	var stock: Dictionary = warehouse.get("liquids", {})
	if not liquid_rates.is_empty():
		_list.add_child(_liquid_card(liquid_rates, accumulated, stock))

	# 常驻说明：这两句话是防止"界面在撒谎"的关键
	var flow: Dictionary = status.get("flow", {})
	_list.add_child(UiKit.wrap_label(
		"生产 ≠ 流入：生产把舱段送进中央仓库、工质由世界自产补进仓库；每次推进才从仓库搬向主装配台（最多 %d 只舱段、每种工质最多 %d 份）。" % [
			int(flow.get("jars", 0)), int(flow.get("liquidPerLiquid", 0))
		], UiKit.FONT_SMALL, UiKit.MUTED))


func _sources_for(producers: Array, shape: String) -> Array:
	var rows := []
	for producer in producers:
		var rates: Dictionary = producer.get("rates", {})
		if not rates.has(shape):
			continue
		var rate := float(rates[shape])
		rows.append({"name": str(producer.get("name", "")), "rate": rate})
	return rows


func _shape_card(generator: Dictionary, sources: Array) -> PanelContainer:
	var shape := str(generator.get("shape", ""))
	var card := UiKit.panel("", UiKit.PANEL_SOFT)
	var box := UiKit.vbox(4)
	card.add_child(box)

	var head := UiKit.hbox(8)
	head.add_child(UiKit.label(shape, UiKit.FONT_BODY, UiKit.TEXT))
	head.add_child(UiKit.spacer())
	head.add_child(UiKit.label("合计 %s / 回合" % UiKit.rate_text(float(generator.get("rate", 0.0))),
		UiKit.FONT_SMALL, UiKit.ACCENT))
	box.add_child(head)

	box.add_child(UiKit.label("累加 %s · 生产源 %d 个" % [
		UiKit.rate_text(float(generator.get("accumulated", 0.0))), int(generator.get("producers", 0))
	], UiKit.FONT_SMALL, UiKit.MUTED))

	for source in sources:
		var row := UiKit.hbox(6)
		row.add_child(UiKit.label(source["name"], UiKit.FONT_SMALL, UiKit.TEXT))
		row.add_child(UiKit.spacer())
		var current: float = source["rate"]
		var on_preset := false
		for preset in RATES:
			if absf(current - float(preset)) < 0.001:
				on_preset = true
				break
		if not on_preset:
			row.add_child(UiKit.label("当前 %s" % UiKit.rate_text(current), UiKit.FONT_SMALL, UiKit.WARN))
		for preset in RATES:
			var rate := float(preset)
			var button := UiKit.small_button(UiKit.rate_text(rate) if rate > 0.0 else "0", 38)
			button.disabled = absf(current - rate) < 0.001
			button.pressed.connect(func() -> void:
				rate_requested.emit(str(source["name"]), shape, rate))
			row.add_child(button)
		row.add_child(_upgrade_button(str(source["name"]), shape, current))
		box.add_child(row)

	return card


## 投矿升一档：花矿石换产线速率。矿石不够或已到顶就灰掉，并把原因写在鼠标提示里。
func _upgrade_button(producer_name: String, shape: String, current: float) -> Button:
	if current >= MAX_RATE - 0.001:
		var maxed := UiKit.small_button("已到顶", 76)
		maxed.disabled = true
		return maxed
	var target := minf(current + UPGRADE_STEP, MAX_RATE)
	var button := UiKit.small_button("投矿 +%s" % UiKit.rate_text(UPGRADE_STEP), 86)
	button.disabled = _ore < UPGRADE_COST
	button.tooltip_text = "花 %d 矿石，把 %s 的 %s 速率提到 %s（现有矿石 %d）" % [
		UPGRADE_COST, producer_name, shape, UiKit.rate_text(target), _ore
	]
	button.pressed.connect(func() -> void:
		upgrade_requested.emit(producer_name, shape, target, UPGRADE_COST))
	return button


func _liquid_card(liquid_rates: Dictionary, accumulated: Dictionary, stock: Dictionary) -> PanelContainer:
	var card := UiKit.panel("", UiKit.PANEL_SOFT)
	var box := UiKit.vbox(4)
	card.add_child(box)
	box.add_child(UiKit.label("工质（世界自产）", UiKit.FONT_BODY, UiKit.TEXT))

	for liquid in liquid_rates.keys():
		var rate := float(liquid_rates[liquid])
		var row := UiKit.hbox(6)
		row.add_child(UiKit.label("%s　自产 %s / 回合" % [str(liquid), UiKit.rate_text(rate)],
			UiKit.FONT_SMALL, UiKit.TEXT))
		row.add_child(UiKit.spacer())
		for preset in RATES:
			var target := float(preset)
			var button := UiKit.small_button(UiKit.rate_text(target) if target > 0.0 else "0", 38)
			button.disabled = absf(rate - target) < 0.001
			button.pressed.connect(func() -> void:
				liquid_rate_requested.emit(str(liquid), target))
			row.add_child(button)
		box.add_child(row)
		box.add_child(UiKit.label("累加 %s · 仓库库存 %d" % [
			UiKit.rate_text(float(accumulated.get(liquid, 0.0))), int(stock.get(liquid, 0))
		], UiKit.FONT_SMALL, UiKit.MUTED))

	return card
