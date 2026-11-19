class_name Health
extends Node
# 生命值组件：只负责"还剩多少血"，不负责护盾、无敌、暴击、吸血。
# 那些属于防御组件与伤害管线，写在生命里会把 owner 搅乱。
#
# 用法：挂成角色子节点，max_value 设成角色的血量上限；
#       DamageReceiver 通过 health_path 找到它并调用 apply_damage()。

signal health_changed(current: int, max_value: int)
signal damaged(amount: int, current: int)
signal died(info: DamageInfo)

@export var max_value: int = 1

var current: int = 0

func _ready() -> void:
	if current <= 0:
		current = max_value
	health_changed.emit(current, max_value)

## 返回真正扣掉的血量（0 表示没扣：已死或数量不合法）
func apply_damage(amount: int, info: DamageInfo = null) -> int:
	if amount <= 0 or current <= 0:
		return 0
	var before := current
	current = maxi(0, current - amount)
	var lost := before - current
	health_changed.emit(current, max_value)
	if lost > 0:
		damaged.emit(lost, current)
	if current == 0:
		died.emit(info)
	return lost

func heal(amount: int) -> int:
	if amount <= 0 or current <= 0:
		return 0
	var before := current
	current = mini(max_value, current + amount)
	var gained := current - before
	if gained > 0:
		health_changed.emit(current, max_value)
	return gained

func set_max(value: int, refill: bool = false) -> void:
	max_value = maxi(1, value)
	current = max_value if refill else mini(current, max_value)
	health_changed.emit(current, max_value)

func is_alive() -> bool:
	return current > 0

func ratio() -> float:
	return 0.0 if max_value <= 0 else float(current) / float(max_value)
