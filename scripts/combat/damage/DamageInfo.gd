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

## attacker_/source_ 故意不标类型：子弹在飞行途中，射手可能已经被打死释放，
## 传进来的就是"已释放的实例"。标成 Node 会在调用处直接抛类型错误，所以这里
## 收下任何值，再统一做有效性检查，失效就降级成"无来源"。
static func make(
		amount_: int,
		type_: StringName = &"legacy",
		attacker_ = null,
		source_ = null,
		hit_position_: Vector2 = Vector2.ZERO,
		critical_: bool = false
) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount_
	info.type = type_
	info.attacker = _alive(attacker_)
	info.source = _alive(source_)
	info.hit_position = hit_position_
	info.critical = critical_
	return info

# 把"已释放"或非 Node 的值统一折成 null
static func _alive(value):
	if value == null:
		return null
	if not (value is Node):
		return null
	if not is_instance_valid(value):
		return null
	return value

func with_tag(tag: StringName) -> DamageInfo:
	if not tags.has(tag):
		tags.append(tag)
	return self

func describe() -> String:
	return "%s %d 点（%s）" % [String(type), amount, "有来源" if attacker != null else "无来源"]
