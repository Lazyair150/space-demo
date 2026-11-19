class_name DamageInfo
extends RefCounted
# 一次攻击的完整描述。攻击载体只负责描述，不碰目标的血量。
#
# 约定：
# - amount 是"攻击方算出来的原始伤害"，防御与减免由受击方的防御组件处理；
# - type 用来区分子弹 / 接触 / 毒 / 爆炸，将来做抗性时按它查表；
# - attacker 是"谁打的"（可能为空：陷阱、毒），source 是载体（子弹、毒实例）。

var attacker: Node
var source: Node
var amount: int = 0
var type: StringName = &"legacy"
var hit_position: Vector2 = Vector2.ZERO
var tags: Array[StringName] = []
## 暴击在攻击方判定，作为请求的一部分传入；进入管线后不会被改写
var critical: bool = false

static func make(
		amount_: int,
		type_: StringName = &"legacy",
		attacker_: Node = null,
		source_: Node = null,
		hit_position_: Vector2 = Vector2.ZERO,
		critical_: bool = false
) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount_
	info.type = type_
	info.attacker = attacker_
	info.source = source_
	info.hit_position = hit_position_
	info.critical = critical_
	return info

func with_tag(tag: StringName) -> DamageInfo:
	if not tags.has(tag):
		tags.append(tag)
	return self

func describe() -> String:
	return "%s %d 点（%s）" % [String(type), amount, "有来源" if attacker != null else "无来源"]
