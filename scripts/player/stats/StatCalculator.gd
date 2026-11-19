extends Node
class_name StatCalculator
# 属性修正汇总器。
#
# 职责边界（第一阶段已锁定）：
#   · 永久成长仍然由 GameState 持有（attack_level），这里不写、不存、不回写任何永久数值；
#   · Buff 只往这里登记临时修正器，到期由 StatusEffectManager 统一撤销；
#   · 本类只做"基础值 + 修正器 → 最终值"的纯计算，不持有计时、不决定谁该存在。
#
# 计算阶段固定为：固定值加算 → 百分比乘算 → 上下限钳制。
# 同一阶段内加算与乘算各自可交换，所以不需要额外排序；真正不可交换的"覆盖/归零"
# 属于钳制阶段，用 bounds 表达。若以后要支持"优先级更高的覆盖"，再加排序字段。

enum Stage { FLAT = 0, MULT = 1 }

var _modifiers: Array = []      # {owner, stat, stage, value}
var _bounds: Dictionary = {}    # stat -> {min, max}

func set_bounds(stat: StringName, min_value: float, max_value: float) -> void:
	_bounds[stat] = {"min": min_value, "max": max_value}

func add_modifier(owner: String, stat: StringName, stage: int, value: float) -> void:
	_modifiers.append({"owner": owner, "stat": stat, "stage": stage, "value": value})

# 撤销某个 owner 的全部修正器，返回撤掉了几条（用于断言"撤干净了"）
func remove_modifiers_by_owner(owner: String) -> int:
	var kept: Array = []
	var removed := 0
	for m in _modifiers:
		if String(m.get("owner", "")) == owner:
			removed += 1
		else:
			kept.append(m)
	_modifiers = kept
	return removed

func clear() -> void:
	_modifiers.clear()

func modifier_count(stat: StringName = &"") -> int:
	if stat == &"":
		return _modifiers.size()
	var n := 0
	for m in _modifiers:
		if StringName(m.get("stat", "")) == stat:
			n += 1
	return n

func owners() -> Array:
	var out: Array = []
	for m in _modifiers:
		var owner := String(m.get("owner", ""))
		if not out.has(owner):
			out.append(owner)
	return out

func value_of(stat: StringName, base: float) -> float:
	var flat := 0.0
	var mult := 1.0
	for m in _modifiers:
		if StringName(m.get("stat", "")) != stat:
			continue
		if int(m.get("stage", Stage.FLAT)) == Stage.MULT:
			mult *= float(m.get("value", 1.0))
		else:
			flat += float(m.get("value", 0.0))

	var value := (base + flat) * mult
	if _bounds.has(stat):
		var bounds: Dictionary = _bounds[stat]
		value = clampf(value, float(bounds.get("min", -INF)), float(bounds.get("max", INF)))
	return value
