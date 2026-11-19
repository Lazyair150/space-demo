class_name DamageResult
extends RefCounted
# 一次伤害的结算结果。它不是"请求"，而是"实际发生了什么"：
# 请求多少、被挡多少、真正扣了多少、是不是致命。
#
# 吸血 / 反伤 / 飘字 / 击杀统计都应该读这里，而不是回头去看目标还剩多少血。

var requested: int = 0
var absorbed: int = 0
var hp_damage: int = 0
var blocked_by: StringName = &"none"
var died: bool = false
var critical: bool = false
var hit_position: Vector2 = Vector2.ZERO
var info: DamageInfo

static func blocked(requested_: int, who: StringName, info_: DamageInfo = null) -> DamageResult:
	var result := DamageResult.new()
	result.requested = requested_
	result.blocked_by = who
	result.info = info_
	if info_ != null:
		result.hit_position = info_.hit_position
	return result

func is_fully_blocked() -> bool:
	return hp_damage == 0

func describe() -> String:
	if absorbed > 0:
		return "请求 %d、吸收 %d、实际 %d%s" % [requested, absorbed, hp_damage, "（致命）" if died else ""]
	if hp_damage == 0:
		return "请求 %d、被 %s 挡下" % [requested, String(blocked_by)]
	return "请求 %d、实际 %d%s" % [requested, hp_damage, "（致命）" if died else ""]
